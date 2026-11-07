// Measure runs a second. Not part of the gate.
//
//   goose build --debug test/measure.goose -o measure
//   ./measure 20000 ok       a trivial target
//   ./measure 100000 abort   a target that aborts on every run
//
// Measure memory outside Goose: /usr/bin/time -f %M ./measure 100000 abort
import std;
import os;
import fuzz from "..";

fn fine(d: const u8[:]) {
}

fn boom(d: const u8[:]) {
    assert(false);
}

thread_fn fine_target() { fuzz::call(fine); }
thread_fn boom_target() { fuzz::call(boom); }

fn main() {
    let argv = args();
    if argv.len < 3 {
        print("usage: measure <runs> ok|abort");
        return 0;
    }
    let n, _ = parse_int(argv[1]);
    var cfg = fuzz::config();
    cfg.seed = 1;
    cfg.runs = n;
    // aborts at one site, so the crasher is saved once, in TMPDIR
    var tmp: u8[>..] = [];
    env("TMPDIR", tmp);
    cfg.crash_root.append(tmp);
    cfg.crash_root.append("/fuzz-measure");
    var rep = fuzz::Report { };
    let t0 = clock_ns();
    if argv[2] == "abort" {
        fuzz::run("measure", cfg, rep, boom_target);
    } else {
        fuzz::run("measure", cfg, rep, fine_target);
    }
    let ms = (clock_ns() - t0) / 1000000;
    var out: u8[>..] = [];
    out.append("runs ");
    format_int(out, rep.runs, 10, 0, ' ');
    out.append(" ms ");
    format_int(out, ms, 10, 0, ' ');
    out.append(" runs/s ");
    format_int(out, rep.runs * 1000 / max(ms, 1), 10, 0, ' ');
    print(out);
    return 0;
}
