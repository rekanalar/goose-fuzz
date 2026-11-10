// Turn the result of a fuzz run into the verdict of a gate.
//
// The program fuzzes a target that never fails. It prints one line with
// the verdict, and it exits with code 1 when the run found something. A
// gate reads that line and that code.
//
//   goose build --debug examples/verdict.goose -o verdict && ./verdict
//
// A test suite can use the same result. The goose-testkit package holds
// a helper that records it as a test result.
//
//   testkit::fuzz_result(t, found, rep.runs, report);
import std;
import os;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "..";

fn never_fails(d: const u8[:]) {
    // The target reads every byte, so the mutations reach the code.
    var sum: i64 = 0;
    for b in d { sum = sum + b; }
    if sum == -1 { abort("unreachable"); }
}

thread_fn target() { fuzz::call(never_fails); }

fn main() {
    var cfg = fuzz::config();
    cfg.runs = 2000;
    var tmp: u8[>..] = [];
    if env("TMPDIR", tmp) {
        cfg.crash_root.append(tmp);
        cfg.crash_root.append("/fuzz-verdict");
    }
    var rep = fuzz::Report { };
    let found = fuzz::run("verdict", cfg, rep, target);
    var out: u8[>..] = [];
    if found == 0 {
        out.append("verdict: PASS, ");
        format_int(out, rep.runs, 10, 0, ' ');
        out.append(" run(s), 0 finding(s)\n");
    } else {
        out.append("verdict: FAIL, ");
        format_int(out, rep.runs, 10, 0, ' ');
        out.append(" run(s), ");
        format_int(out, found, 10, 0, ' ');
        out.append(" finding(s)\n");
        var report: u8[>..] = [];
        fuzz::format_report(report, rep);
        out.append(report);
    }
    print(out);
    if found != 0 || rep.save_failed > 0 {
        exit(1);
    }
    return 0;
}
