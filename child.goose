// The child side of the child mode.
//
// One child process runs one batch. It writes every input to the saved
// path before it runs it, so the parent can read the last one after a
// death. The root file of the program declares the process package.
namespace fuzz;

import std;
import os;

// The marker that tells a program it runs as a child of the parent.
const CHILD_MARKER = "--fuzz-child";

// The position of the marker in args(), or -1.
fn marker_index() -> i64 {
    let a = args();
    for i in 0..a.len {
        if a[i] == CHILD_MARKER {
            return i;
        }
    }
    return -1;
}

// True when args() holds the marker of the child side.
fn is_child() -> bool {
    return marker_index() >= 0;
}

// The exit code of a child-side error.
const CHILD_ERROR = 126;

// One argument as a number. False when the argument is missing or is not
// a number.
fn arg_int(a: u8[:][>..]&, k: i64, out: i64&) -> bool {
    if k >= a.len {
        return false;
    }
    let v, ok = parse_int(a[k]);
    if !ok {
        return false;
    }
    out = v;
    return true;
}

// The child side. Reads the seven arguments after the marker, in the
// order seed_dir, max_len, seed, runs, saved path, crash root, name.
// Loads the seeds, runs the batch, and writes each input to the saved
// path before the run. A contained abort saves a crasher, like run does.
// Returns 0 for a clean batch, 126 for a child-side error.
fn child_batch<W>() -> i32 {
    let a = args();
    let mark = marker_index();
    if mark < 0 || mark + 7 >= a.len {
        return CHILD_ERROR;
    }
    let seed_dir = a[mark + 1];
    var max_len: i64 = 0;
    var seed_n: i64 = 0;
    var runs: i64 = 0;
    if !arg_int(a, mark + 2, max_len) {
        return CHILD_ERROR;
    }
    if !arg_int(a, mark + 3, seed_n) {
        return CHILD_ERROR;
    }
    if !arg_int(a, mark + 4, runs) {
        return CHILD_ERROR;
    }
    let save_path = a[mark + 5];
    let crash_root = a[mark + 6];
    let name = a[mark + 7];
    if runs <= 0 || max_len <= 1 {
        return CHILD_ERROR;
    }
    var pool: u8[>..] = [];
    var ends: i64[>..] = [];
    if seed_dir.len > 0 {
        if load_seeds(seed_dir, max_len, pool, ends) < 0 {
            return CHILD_ERROR;
        }
    }
    let first = max(ends.len, 1);
    var r = rng { seed_n as u64 };
    var cur: u8[>..] = [];
    var why: u8[>..] = [];
    for i in 0..runs {
        cur.clear();
        if i < ends.len {
            cur.append(seed_at(pool, ends, i, max_len));
        } else if i >= first {
            mutate_next(r, pool, ends, max_len, cur);
        }
        // The input reaches the file before the run. A death then leaves
        // the input that caused it.
        write_file(save_path, cur);
        if !run_one(cur, why, W) {
            save_crasher(crash_root, name, cur);
        }
    }
    return 0;
}
