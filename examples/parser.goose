// Fuzz a small parser that has one planted bug.
//
// The input is one length byte, then the payload. The parser trusts the
// length byte, so a length above the input size reads past the end.
//
//   goose build --debug examples/parser.goose -o parser && ./parser
//   ./parser replay
//
// A real program calls exit(1) when the run finds something, so a gate fails
// on a finding. This example plants its bug, so it reports and returns 0. A return from main does not set the
// exit code of a built program, so use exit.
import std;
import os;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "..";

fn parse(d: const u8[:]) {
    if d.len == 0 {
        return;
    }
    let n = d[0] as i64;
    if n > 0 {
        let _ = d[n];
    }
}

thread_fn target() { fuzz::call(parse); }

fn main() {
    let argv = args();
    var cfg = fuzz::config();
    cfg.runs = 2000;
    // Keep the crashers out of the source tree when TMPDIR is set.
    var tmp: u8[>..] = [];
    if env("TMPDIR", tmp) {
        cfg.crash_root.append(tmp);
        cfg.crash_root.append("/fuzz-example");
    }
    var rep = fuzz::Report { };
    var out: u8[>..] = [];
    if argv.len > 1 && argv[1] == "replay" {
        let failed = fuzz::replay("parser", cfg.crash_root, rep, target);
        out.append("replayed crashers that still abort: ");
        format_int(out, failed, 10, 0, ' ');
        print(out);
        if failed > 0 {
            exit(1);
        }
        return 0;
    }
    let found = fuzz::run("parser", cfg, rep, target);
    fuzz::format_report(out, rep);
    print(out);
    // -1 means the seed directory failed. A failed save loses a crasher.
    if found < 0 || rep.save_failed > 0 {
        exit(1);
    }
    return 0;
}
