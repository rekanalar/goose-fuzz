// Targets with planted aborts, for the test suite.
//
// Each target is a plain fn and a one-line thread_fn.
namespace targets;

import std;
import fuzz from "..";

fn ok_fn(d: const u8[:]) {
}

fn assert_fn(d: const u8[:]) {
    if d.len > 0 && d[0] == 7 {
        assert(false);
    }
}

fn index_fn(d: const u8[:]) {
    let xs = [1, 2, 3];
    if d.len > 0 && d[0] > 100 {
        let k = d[0] as i64;
        let _ = xs[k];
    }
}

fn div_fn(d: const u8[:]) {
    if d.len > 0 && d[0] == 9 {
        let z = d[0] - d[0];
        let _ = 10 / (z as i64);
    }
}

fn overflow_fn(d: const u8[:]) {
    if d.len > 0 && d[0] == 200 {
        var x: i32 = 2147483647;
        x = x + d[0];
        let _ = x;
    }
}

fn prefix_fn(d: const u8[:]) {
    if d.len >= 3 && d[0] == 3 && d[1] == 1 && d[2] == 4 {
        assert(false);
    }
}

fn two_fn(d: const u8[:]) {
    if d.len > 0 && d[0] == 1 {
        assert(false);
    }
    if d.len > 0 && d[0] == 2 {
        assert(false);
    }
}

fn always_fn(d: const u8[:]) {
    assert(false);
}

fn exit_fn(d: const u8[:]) {
    if d.len > 0 && d[0] == 61 {
        exit(3);
    }
}

fn hang_fn(d: const u8[:]) {
    if d.len > 0 && d[0] == 62 {
        sleep_ms(30000);
    }
}

thread_fn always_target() { fuzz::call(always_fn); }
thread_fn exit_target() { fuzz::call(exit_fn); }
thread_fn hang_target() { fuzz::call(hang_fn); }
thread_fn ok_target() { fuzz::call(ok_fn); }
thread_fn assert_target() { fuzz::call(assert_fn); }
thread_fn index_target() { fuzz::call(index_fn); }
thread_fn div_target() { fuzz::call(div_fn); }
thread_fn overflow_target() { fuzz::call(overflow_fn); }
thread_fn prefix_target() { fuzz::call(prefix_fn); }
thread_fn two_target() { fuzz::call(two_fn); }

fn law_true(d: const u8[:]) -> bool {
    return true;
}

fn law_nine(d: const u8[:]) -> bool {
    return !(d.len > 0 && d[0] == 9);
}

thread_fn law_true_target() { fuzz::call_law(law_true); }
thread_fn law_nine_target() { fuzz::call_law(law_nine); }
