// The C part of the goose-fuzz package.
//
// It records the code that each input reaches, and how often each
// piece ran. The compiler of a program that was built with the
// coverage flag calls the callback below at every edge of the
// generated C. The callback puts the return address in a table and
// counts the hits of the current input. The end of an input maps every
// count to a class, counts the classes that rose above the class of
// any earlier input, and keeps the highest class of the run.
//
// The functions take the types that the Goose compiler generates.
// goose.h is on the include path of every native part.

#include "goose.h"

#include <stdint.h>
#include <string.h>

// The number of the slots of the table.
#define GS_COV_SLOTS 65536u

// The table of the addresses. The address 0 means that the slot is free.
static uintptr_t gs_cov_table[GS_COV_SLOTS];

// The hits of the current input, one counter per slot.
static uint32_t gs_cov_count[GS_COV_SLOTS];

// The highest class of the run, one byte per slot.
static uint8_t gs_cov_virgin[GS_COV_SLOTS];

// The input that owns the count of the slot. A count of an older input
// is stale, and the input counter tells them apart.
static uint32_t gs_cov_seen[GS_COV_SLOTS];

// The slots that the current input reached, once each. The end of an
// input walks this list, so the cost stays at the edges that ran.
static uint32_t gs_cov_touched[GS_COV_SLOTS];
static uint32_t gs_cov_ntouched = 0;

// The number of the current input. It grows at every begin.
static uint32_t gs_cov_epoch = 0;

// The count of the distinct addresses since the last reset.
static uint64_t gs_cov_total = 0;

// The count of the addresses that found no free slot. The table is full.
static uint64_t gs_cov_lost = 0;

// The count of the classes that rose during the last closed bracket.
static uint64_t gs_cov_rises_last = 0;

// The edges whose highest class is the index. The index 0 holds no
// edge: an edge that no input reached has no class yet, and the Goose
// side takes it as the distinct edges minus the rest.
static uint64_t gs_cov_classes[9];

// True while a bracket is open. The machinery of the fuzzer runs
// outside a bracket, and its addresses never rise.
static int gs_cov_active = 0;

// True on the thread that opened the bracket. Only that thread records
// edges. The main thread waits for the worker in a loop of its own, and
// the counts of that loop would change with the speed of the machine.
// The flag lives in the thread, so it needs no lock.
#if defined(__GNUC__) || defined(__clang__)
static __thread int gs_cov_mine = 0;
#else
static int gs_cov_mine = 0;
#endif

// True when a callback came. It says that the program has the coverage.
static int gs_cov_here = 0;

// True while the callback runs. It stops the callback from calling
// itself when this file is instrumented too.
static int gs_cov_busy = 0;

// The callback must not be instrumented. The compiler of the build
// compiles this file with the same wrapper, and an instrumented
// callback calls itself until the program dies.
#if defined(__GNUC__) || defined(__clang__)
#define GS_COV_CLEAN __attribute__((no_sanitize_coverage))
#else
#define GS_COV_CLEAN
#endif

// The class of a hit count. One input that runs an edge 200 times
// reaches the last class, and one that runs it once reaches the second.
static uint8_t gs_cov_class_of(uint32_t n) {
    if (n == 0) return 0;
    if (n == 1) return 1;
    if (n == 2) return 2;
    if (n == 3) return 3;
    if (n <= 7) return 4;
    if (n <= 15) return 5;
    if (n <= 31) return 6;
    if (n <= 127) return 7;
    return 8;
}

// The callback of the sanitizer. It comes at every edge of the
// generated C. It puts the address in the table, and it counts the hit
// in the counter of the slot. An address that finds the table full is
// counted as lost.
//
// MSVC has no coverage flag and no __builtin_return_address, so it
// compiles no callback. A program built with MSVC has no coverage.
#if defined(__GNUC__) || defined(__clang__)
GS_COV_CLEAN void __sanitizer_cov_trace_pc(void) {
    gs_cov_here = 1;
    if (!gs_cov_mine || gs_cov_busy) return;
    gs_cov_busy = 1;
    uintptr_t addr = (uintptr_t)__builtin_return_address(0);
    uint32_t at = (uint32_t)((addr >> 4) * 2654435761u) & (GS_COV_SLOTS - 1u);
    uint32_t i = 0;
    uint32_t slot = 0;
    int placed = 0;
    while (i < GS_COV_SLOTS) {
        slot = (at + i) & (GS_COV_SLOTS - 1u);
        if (gs_cov_table[slot] == addr) {
            placed = 1;
            break;
        }
        if (gs_cov_table[slot] == 0) {
            gs_cov_table[slot] = addr;
            gs_cov_total++;
            placed = 1;
            break;
        }
        i++;
    }
    if (!placed) {
        gs_cov_lost++;
    } else if (gs_cov_seen[slot] != gs_cov_epoch) {
        // The first hit of this input. The count starts at one, and
        // the slot joins the list that the end of the input walks.
        gs_cov_seen[slot] = gs_cov_epoch;
        gs_cov_count[slot] = 1;
        if (gs_cov_ntouched < GS_COV_SLOTS) {
            gs_cov_touched[gs_cov_ntouched] = slot;
            gs_cov_ntouched++;
        }
    } else {
        gs_cov_count[slot]++;
    }
    gs_cov_busy = 0;
}
#endif

// Empty the table, the counters and the classes. A run calls it at its
// start, so that the counts belong to one run.
GS_COV_CLEAN void gs_cov_reset(void) {
    memset(gs_cov_table, 0, sizeof gs_cov_table);
    memset(gs_cov_count, 0, sizeof gs_cov_count);
    memset(gs_cov_virgin, 0, sizeof gs_cov_virgin);
    memset(gs_cov_seen, 0, sizeof gs_cov_seen);
    memset(gs_cov_classes, 0, sizeof gs_cov_classes);
    gs_cov_ntouched = 0;
    gs_cov_epoch = 0;
    gs_cov_total = 0;
    gs_cov_lost = 0;
    gs_cov_rises_last = 0;
    gs_cov_active = 0;
}

// Open the bracket of one input. The input counter grows, so the
// counts of the older inputs go stale, and the list of the touched
// slots starts empty.
GS_COV_CLEAN void gs_cov_begin(void) {
    gs_cov_epoch++;
    gs_cov_ntouched = 0;
    gs_cov_active = 1;
    gs_cov_mine = 1;
}

// Close the bracket of one input. It gives the count of the edges
// whose class rose above the class of any earlier input of the run. A
// new edge rises too, because its class leaves zero. The worker of the
// input closes it. The main thread closes it after an abort.
GS_COV_CLEAN uint64_t gs_cov_end(void) {
    if (gs_cov_active) {
        uint64_t rises = 0;
        for (uint32_t k = 0; k < gs_cov_ntouched; k++) {
            uint32_t slot = gs_cov_touched[k];
            uint8_t cls = gs_cov_class_of(gs_cov_count[slot]);
            if (cls > gs_cov_virgin[slot]) {
                gs_cov_classes[cls]++;
                if (gs_cov_virgin[slot] > 0) {
                    gs_cov_classes[gs_cov_virgin[slot]]--;
                }
                gs_cov_virgin[slot] = cls;
                rises++;
            }
        }
        gs_cov_ntouched = 0;
        gs_cov_rises_last = rises;
        gs_cov_active = 0;
    }
    gs_cov_mine = 0;
    return gs_cov_rises_last;
}

// The count of the distinct addresses since the last reset.
GS_COV_CLEAN uint64_t gs_cov_total_edges(void) {
    return gs_cov_total;
}

// The count of the addresses that found the table full.
GS_COV_CLEAN uint64_t gs_cov_lost_edges(void) {
    return gs_cov_lost;
}

// The count of the edges whose highest class is cls, from 1 to 8. The
// class 0 holds no edge here; the Goose side takes the class 0 as the
// distinct edges minus the rest.
GS_COV_CLEAN uint64_t gs_cov_class_edges(int64_t cls) {
    if (cls < 1 || cls > 8) {
        return 0;
    }
    return gs_cov_classes[cls];
}

// True when the program was built with the coverage flag.
GS_COV_CLEAN uint8_t gs_cov_live(void) {
    return (uint8_t)(gs_cov_here ? 1 : 0);
}

// Write the path of the compiler wrapper of the package into out. The
// file knows its own path, and the compiler gives an absolute path to
// the C of a package. False when the path does not have the expected
// form.
GS_COV_CLEAN uint8_t gs_cov_script(gs_rref out) {
    static const char self[] = __FILE__;
    static const char mark[] = "/src/cov.c";
    size_t n = sizeof self - 1;
    size_t m = sizeof mark - 1;
    if (n < m || memcmp(self + n - m, mark, m) != 0) return 0;
    gs_bld_append(out, self, (int64_t)(n - m));
    gs_bld_append(out, "/cov-cc", 7);
    return 1;
}
