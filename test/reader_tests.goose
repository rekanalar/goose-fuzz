// The tests of the reader: the ranges, the defaults and the determinism.
namespace reader_tests;

import std;
import os;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "..";
import targets;
import work_dirs;
import seed_pool;

// The reader: the ranges, the defaults, and the determinism.
fn test_reader() {
    // the defaults on an empty input
    var r = fuzz::reader("");
    assert(!fuzz::read_bool(r));
    assert(fuzz::read_i64(r, -5, 5) == 0);
    assert(fuzz::read_i64(r, 1000, 1010) == 0);
    assert(fuzz::read_string(r, 8).len == 0);
    assert(fuzz::read_i64_list(r, 4).len == 0);
    // a refused range returns 0 and consumes nothing
    var buf: u8[>..] = [];
    buf.resize(32, 200);
    var r2 = fuzz::reader(buf);
    assert(fuzz::read_i64(r2, 10, 1) == 0);
    assert(r2.pos == 0);
    // every value stays in its range, over random inputs
    var rng1 = rng { 9 };
    var bytes: u8[>..] = [];
    for i in 0..500 {
        bytes.clear();
        let n = rng1.rand_int(33);
        for k in 0..n {
            bytes.push(rng1.rand_int(256) as u8);
        }
        var rr = fuzz::reader(bytes);
        if n == 0 {
            // the defaults of an empty input: false and 0
            assert(!fuzz::read_bool(rr));
            assert(fuzz::read_i64(rr, 1000, 1010) == 0);
            continue;
        }
        let v = fuzz::read_i64(rr, 1000, 1010);
        assert(v >= 1000 && v <= 1010);
        if rr.pos < rr.data.len {
            // bytes remain, so the value maps into the range
            let w = fuzz::read_i64(rr, -7, -3);
            assert(w >= -7 && w <= -3);
        }
        fuzz::read_bool(rr);
        fuzz::read_string(rr, 9);
        fuzz::read_i64_list(rr, 5);
    }
    // the same bytes give the same values twice
    var fixed: u8[>..] = [];
    for i in 0..40 {
        fixed.push(((i * 7 + 3) % 256) as u8);
    }
    var r3 = fuzz::reader(fixed);
    var r4 = fuzz::reader(fixed);
    assert(fuzz::read_i64(r3, 0, 1000000) == fuzz::read_i64(r4, 0, 1000000));
    assert(fuzz::read_bool(r3) == fuzz::read_bool(r4));
    assert(fuzz::read_string(r3, 5) == fuzz::read_string(r4, 5));
    assert(fuzz::read_i64_list(r3, 3) == fuzz::read_i64_list(r4, 3));
    // a list holds what the bytes give, up to the maximum
    var lst: u8[>..] = [];
    lst.push(10);
    for i in 0..40 {
        lst.push(i as u8);
    }
    var r5 = fuzz::reader(lst);
    let xs = fuzz::read_i64_list(r5, 3);
    assert(xs.len == 3);
    var r6 = fuzz::reader(lst);
    let ys = fuzz::read_i64_list(r6, 100);
    assert(ys.len == 5);
    // a short list gives the items that the bytes hold
    var short: u8[>..] = [];
    short.push(4);
    short.push(1);
    short.push(2);
    var r7 = fuzz::reader(short);
    assert(fuzz::read_i64_list(r7, 10).len == 0);
}
