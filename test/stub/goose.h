// A stand-in for the header that the Goose compiler supplies to a native
// part. The overflow test builds src/cov.c outside the compiler, so it
// needs the few names that the file uses.
#ifndef GS_TEST_STUB_GOOSE_H
#define GS_TEST_STUB_GOOSE_H

#include <stddef.h>
#include <stdint.h>

typedef void *gs_rref;

static inline void gs_bld_append(gs_rref out, const char *s, int64_t n) {
    (void)out;
    (void)s;
    (void)n;
}

#endif
