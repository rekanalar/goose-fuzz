// A 64-bit FNV-1a hash, for crasher file names.
//
// The standard library hash may change between releases. A file name that
// depended on it could differ between compilers. This hash cannot change.
namespace fuzz;

import std;

// FNV-1a 64-bit: offset basis 14695981039346656037, prime 1099511628211.
fn fnv1a64(data: const u8[:]) -> u64 {
    var h: u64 = 14695981039346656037;
    for b in data {
        h = (h ^ b) * 1099511628211;
    }
    return h;
}

// Append v as 16 lowercase hex digits, padded with zeros.
fn hex16(out: u8[>..]&, v: u64) {
    format_uint(out, v, 16, 16, '0');
}
