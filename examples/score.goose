// Steer a run with a score and a mutator of the caller.
//
// The target aborts on an input with eight letters A. A blind byte flip
// seldom builds that input. The target reports the count of its letters
// as a score, and the run mutates the input with the best score. The
// mutator of the caller adds one letter A to its input.
//
//   goose build --debug examples/score.goose -o score && ./score
import std;
import os;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "..";

fn count_a(d: const u8[:]) {
    var n: i64 = 0;
    for i in 0..d.len {
        if d[i] == 'A' {
            n += 1;
        }
    }
    fuzz::score(n as f64);
    if n >= 8 {
        assert(false);
    }
}

thread_fn target() { fuzz::call(count_a); }

// The mutator takes the input and a buffer. It returns true when it wrote
// an input.
fn add_a(data: const u8[:], out: u8[>..]&) -> bool {
    out.append(data);
    out.push('A');
    return true;
}

fn main() {
    var cfg = fuzz::config();
    cfg.runs = 2000;
    cfg.seed = 1;
    cfg.score_mode = 1;
    cfg.mutator_rate = 50;
    // Keep the crashers out of the source tree.
    var root: u8[>..] = [];
    if !env("TMPDIR", root) {
        root.append("/tmp");
    }
    root.append("/fuzz-score-example");
    cfg.crash_root.append(root);
    var rep = fuzz::Report { };
    let found = fuzz::run_with("score", cfg, rep, target, add_a);
    var out: u8[>..] = [];
    fuzz::format_report(out, rep);
    print(out);
    if found != 1 {
        exit(1);
    }
    return 0;
}
