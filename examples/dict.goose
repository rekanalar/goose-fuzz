// Fuzz a parser with a dictionary of tokens.
//
// The parser accepts only inputs that start with REQ. Blind byte flips
// rarely build that word. The dictionary holds it, so the mutator finds
// the planted bug.
//
//   goose build --debug examples/dict.goose -o dict && ./dict
import std;
import os;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "..";

fn parse(d: const u8[:]) {
    if d.len >= 3 && d[0..3] == "REQ" {
        assert(false);
    }
}

thread_fn target() { fuzz::call(parse); }

fn main() {
    var cfg = fuzz::config();
    cfg.runs = 2000;
    // The dictionary comes from a file and from an added token.
    var tmp: u8[>..] = [];
    if !env("TMPDIR", tmp) {
        tmp.append("/tmp");
    }
    var dpath: u8[>..] = [];
    dpath.append(tmp);
    dpath.append("/fuzz-dict-example.txt");
    var words: u8[>..] = [];
    words.append("# the words of the protocol\n");
    words.append("word=\"REQ\"\n");
    assert(write_file(dpath, words));
    var err: u8[>..] = [];
    if !fuzz::dict_load(cfg, dpath, err) {
        print(err);
        exit(1);
    }
    if !fuzz::dict_add(cfg, "RSP") {
        exit(1);
    }
    // Keep the crashers out of the source tree.
    var root: u8[>..] = [];
    root.append(tmp);
    root.append("/fuzz-dict-example");
    cfg.crash_root.append(root);
    var rep = fuzz::Report { };
    let found = fuzz::run("dict", cfg, rep, target);
    var out: u8[>..] = [];
    fuzz::format_report(out, rep);
    print(out);
    delete_file(dpath);
    if found != 1 {
        exit(1);
    }
    return 0;
}
