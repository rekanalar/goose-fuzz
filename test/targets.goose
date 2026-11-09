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

fn goose_fn(d: const u8[:]) {
    if d.len >= 5 && d[0..5] == "GOOSE" {
        assert(false);
    }
}

fn typed_fn(r: fuzz::Reader&) {
    let n = fuzz::read_i64(r, 1000, 1010);
    let flag = fuzz::read_bool(r);
    let s = fuzz::read_string(r, 8);
    let xs = fuzz::read_i64_list(r, 4);
    let _ = s.len + xs.len;
    if n > 1005 && flag {
        assert(false);
    }
}

fn slow_fn(d: const u8[:]) {
    sleep_ms(1);
}

// A target that sleeps twelve seconds. The child stops it at ten, and
// the probe of the parent ends it within its own time.
fn slow12_fn(d: const u8[:]) {
    if d.len > 0 {
        sleep_ms(12000);
    }
}

// A target that gives the current input a score. The score is the
// length of the input.
fn score_fn(d: const u8[:]) {
    fuzz::score(d.len);
}

// A target that aborts on an input of eight mark bytes at its end.
fn mark_fn(d: const u8[:]) {
    if d.len >= 8 {
        var all = true;
        for i in 0..8 {
            if d[d.len - 8 + i] != 250 {
                all = false;
                break;
            }
        }
        if all {
            assert(false);
        }
    }
}

// A target that refuses an input that is longer than the limit.
fn len_fn(d: const u8[:]) {
    assert(d.len <= 4096);
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
thread_fn goose_target() { fuzz::call(goose_fn); }
thread_fn typed_target() { fuzz::call_typed(typed_fn); }
thread_fn slow_target() { fuzz::call(slow_fn); }
thread_fn slow12_target() { fuzz::call(slow12_fn); }
thread_fn score_target() { fuzz::call(score_fn); }
thread_fn mark_target() { fuzz::call(mark_fn); }
thread_fn len_target() { fuzz::call(len_fn); }

fn law_true(d: const u8[:]) -> bool {
    return true;
}

fn law_nine(d: const u8[:]) -> bool {
    return !(d.len > 0 && d[0] == 9);
}

thread_fn law_true_target() { fuzz::call_law(law_true); }
thread_fn law_nine_target() { fuzz::call_law(law_nine); }
