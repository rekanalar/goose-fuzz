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

// The child side. Reads the arguments after the marker, in the order
// seed_dir, max_len, seed, runs, saved path, crash root, name. A parent
// that holds a dictionary appends the dictionary path and the token
// rate as an eighth and a ninth argument. Seven arguments still mean no
// dictionary, so an old parent keeps working. A tenth argument is the
// path of a status file: the child writes the count of its aborts
// there, and the probe of the parent reads it. Loads the seeds, runs
// the batch, and writes each input to the saved path before the run. A
// contained abort saves a crasher, like run does. Returns 0 for a clean
// batch, 126 for a child-side error.
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
    // The dictionary travels as the eighth argument, with the token rate
    // as the ninth. A bad line in the file is skipped; the tokens before
    // it stay.
    var rate: i64 = DEFAULT_TOKEN_RATE;
    var dpool: u8[>..] = [];
    var dends: i64[>..] = [];
    if mark + 8 < a.len {
        var dtext: u8[>..] = [];
        var derr: u8[>..] = [];
        if read_file(a[mark + 8], dtext) {
            dict_parse(dtext, dpool, dends, derr);
        }
        if mark + 9 < a.len {
            arg_int(a, mark + 9, rate);
        }
    }
    // The status path is the tenth argument. The probe of the parent
    // reads the count of the aborts from it.
    var status_path: u8[>..] = [];
    if mark + 10 < a.len {
        status_path.append(a[mark + 10]);
    }
    var pool: u8[>..] = [];
    var seeds: Seed[>..] = [];
    if seed_dir.len > 0 {
        if load_seeds(seed_dir, max_len, DEFAULT_ENERGY, pool, seeds) < 0 {
            return CHILD_ERROR;
        }
    }
    let first = max(seeds.len, 1);
    var r = rng { seed_n as u64 };
    var cur: u8[>..] = [];
    var why: u8[>..] = [];
    var src: i64 = -1;
    var aborts: i64 = 0;
    for i in 0..runs {
        cur.clear();
        if i < seeds.len {
            cur.append(seed_at(pool, seeds, i, max_len));
        } else if i >= first {
            mutate_next_dict(r, pool, seeds, max_len, 0, dpool, dends, rate, cur, src);
        }
        // The input reaches the file before the run. A death then leaves
        // the input that caused it.
        write_file(save_path, cur);
        if !run_one(cur, why, W) {
            save_crasher(crash_root, name, cur);
            aborts += 1;
        }
    }
    if status_path.len > 0 {
        var line: u8[>..] = [];
        format_int(line, aborts, 10, 0, ' ');
        write_file(status_path, line);
    }
    return 0;
}
