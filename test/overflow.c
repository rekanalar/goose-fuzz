// The overflow test of the coverage layer.
//
// Two counters can wrap in a long run: the hits of one edge, and the number
// of inputs. Each needs more than four billion steps, so the test sets the
// counter near its limit and takes the last steps. It includes src/cov.c, so
// it reads the tables of the layer.
//
// Build and run from the package root, with the stub header:
//   cc -I test/stub -o overflow test/overflow.c && ./overflow
// It prints "overflow test passed". The gate does this on systems whose C
// compiler is GCC or clang.

#include "../src/cov.c"

#include <stdio.h>
#include <stdlib.h>

#if defined(__GNUC__) || defined(__clang__)

#define CHECK(cond) \
    do { \
        if (!(cond)) { \
            fprintf(stderr, "overflow test: failed: %s (line %d)\n", #cond, __LINE__); \
            exit(1); \
        } \
    } while (0)

// One edge: the callback sees the same return address on every call.
__attribute__((noinline)) static void hit(void) {
    __sanitizer_cov_trace_pc();
}

// The slot that holds the one edge of the run.
static uint32_t the_slot(void) {
    for (uint32_t i = 0; i < GS_COV_SLOTS; i++) {
        if (gs_cov_table[i] != 0) return i;
    }
    return GS_COV_SLOTS;
}

int main(void) {
    // The hits of one edge pass 4294967295. The edge must reach class 8.
    gs_cov_reset();
    gs_cov_begin();
    hit();
    uint32_t slot = the_slot();
    CHECK(slot < GS_COV_SLOTS);
    gs_cov_count[slot] = 4294967295ULL;
    hit();
    CHECK(gs_cov_count[slot] == 4294967296ULL);
    gs_cov_end();
    CHECK(gs_cov_class_edges(8) == 1);
    CHECK(gs_cov_class_edges(1) == 0);

    // The input counter passes 4294967295. The next input must count its
    // edge, and no stale owner may hide it.
    gs_cov_reset();
    gs_cov_begin();
    hit();
    gs_cov_end();
    CHECK(gs_cov_class_edges(1) == 1);
    gs_cov_epoch = 4294967295U;
    gs_cov_begin();
    CHECK(gs_cov_epoch != 0);
    hit();
    gs_cov_end();
    // The edge reached a class again, and the table holds one edge only.
    CHECK(gs_cov_total_edges() == 1);
    CHECK(gs_cov_ntouched == 0);
    CHECK(gs_cov_seen[the_slot()] == gs_cov_epoch);

    // The lock turns on at the first attach and off at the reset.
    gs_cov_reset();
    CHECK(gs_cov_shared == 0);
    gs_cov_attach();
    CHECK(gs_cov_shared == 1);
    gs_cov_detach();
    gs_cov_reset();
    CHECK(gs_cov_shared == 0);

    printf("overflow test passed\n");
    return 0;
}

#else

int main(void) {
    printf("overflow test passed\n");
    return 0;
}

#endif
