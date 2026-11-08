// The C part of the goose-fuzz package.
//
// It records the code that each input reaches. The compiler of a
// program that was built with the coverage flag calls the callback
// below at every edge of the generated C. The callback puts the return
// address in a table. A slot holds one address, and the count of the
// addresses rises when an address takes a free slot.
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

// The count of the distinct addresses since the last reset.
static uint64_t gs_cov_total = 0;

// The count of the addresses that found no free slot. The table is full.
static uint64_t gs_cov_lost = 0;

// The count of the addresses that came since the last begin.
static uint64_t gs_cov_new = 0;

// The count of the last closed bracket.
static uint64_t gs_cov_last = 0;

// True while a bracket is open. The machinery of the fuzzer runs
// outside a bracket, and its addresses never count as new.
static int gs_cov_active = 0;

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

// The callback of the sanitizer. It comes at every edge of the
// generated C. It puts the address in the table, and it counts the
// address when no earlier input reached it. An address that finds the
// table full is counted as lost.
//
// MSVC has no coverage flag and no __builtin_return_address, so it
// compiles no callback. A program built with MSVC has no coverage.
#if defined(__GNUC__) || defined(__clang__)
GS_COV_CLEAN void __sanitizer_cov_trace_pc(void) {
    if (gs_cov_busy) return;
    gs_cov_busy = 1;
    uintptr_t addr = (uintptr_t)__builtin_return_address(0);
    uint32_t at = (uint32_t)((addr >> 4) * 2654435761u) & (GS_COV_SLOTS - 1u);
    uint32_t i = 0;
    int placed = 0;
    while (i < GS_COV_SLOTS) {
        uint32_t slot = (at + i) & (GS_COV_SLOTS - 1u);
        if (gs_cov_table[slot] == addr) {
            placed = 1;
            break;
        }
        if (gs_cov_table[slot] == 0) {
            gs_cov_table[slot] = addr;
            gs_cov_total++;
            if (gs_cov_active) gs_cov_new++;
            placed = 1;
            break;
        }
        i++;
    }
    if (!placed) gs_cov_lost++;
    gs_cov_here = 1;
    gs_cov_busy = 0;
}
#endif

// Empty the table and the counters. A run calls it at its start, so
// that the counts belong to one run.
GS_COV_CLEAN void gs_cov_reset(void) {
    memset(gs_cov_table, 0, sizeof gs_cov_table);
    gs_cov_total = 0;
    gs_cov_lost = 0;
    gs_cov_new = 0;
    gs_cov_last = 0;
    gs_cov_active = 0;
}

// Open the bracket of one input.
GS_COV_CLEAN void gs_cov_begin(void) {
    gs_cov_new = 0;
    gs_cov_active = 1;
}

// Close the bracket of one input. Gives the count of the edges that no
// earlier input reached. The worker of the input closes it. The main
// thread closes it after an abort.
GS_COV_CLEAN uint64_t gs_cov_end(void) {
    if (gs_cov_active) {
        gs_cov_last = gs_cov_new;
        gs_cov_active = 0;
    }
    return gs_cov_last;
}

// The count of the distinct addresses since the last reset.
GS_COV_CLEAN uint64_t gs_cov_total_edges(void) {
    return gs_cov_total;
}

// The count of the addresses that found the table full.
GS_COV_CLEAN uint64_t gs_cov_lost_edges(void) {
    return gs_cov_lost;
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
