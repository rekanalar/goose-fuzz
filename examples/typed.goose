// Fuzz a target that reads typed values.
//
// The target takes a number in a range and a flag from a Reader over the
// mutated bytes. The saved crasher stays a byte file, so it replays.
//
//   goose build --debug examples/typed.goose -o typed && ./typed
import std;
import os;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "..";

fn logic(r: fuzz::Reader&) {
    let n = fuzz::read_i64(r, 0, 100);
    let flag = fuzz::read_bool(r);
    let name = fuzz::read_string(r, 8);
    let _ = flag && name.len > 0;
    if n > 90 {
        assert(false);
    }
}

thread_fn target() { fuzz::call_typed(logic); }

fn main() {
    var cfg = fuzz::config();
    cfg.runs = 2000;
    var tmp: u8[>..] = [];
    if !env("TMPDIR", tmp) {
        tmp.append("/tmp");
    }
    var root: u8[>..] = [];
    root.append(tmp);
    root.append("/fuzz-typed-example");
    cfg.crash_root.append(root);
    var rep = fuzz::Report { };
    let found = fuzz::run("typed", cfg, rep, target);
    var out: u8[>..] = [];
    fuzz::format_report(out, rep);
    print(out);
    // The crasher holds bytes, so the replay works on it unchanged.
    let failed = fuzz::replay("typed", cfg.crash_root, rep, target);
    var tail: u8[>..] = [];
    tail.append("replayed crashers that still abort: ");
    format_int(tail, failed, 10, 0, ' ');
    print(tail);
    if found != 1 {
        exit(1);
    }
    return 0;
}
