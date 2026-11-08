// Fuzz a target with coverage guidance.
//
// The target opens three stages, one byte for each. A blind run seldom
// reaches the abort. A run built with the coverage compiler keeps each
// input that opens a stage, and it finds the abort.
//
//   goose build --debug examples/coverage.goose -o coverage && ./coverage
//
// The plain build prints the path of the coverage compiler and runs with
// no guidance. Build again with the script to turn the guidance on:
//
//   GOOSE_CC=<the path printed above> goose build --debug examples/coverage.goose -o coverage
import std;
import os;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "..";

fn staged(d: const u8[:]) {
    if d.len > 0 && d[0] == 'G' {
        if d.len > 1 && d[1] == 'O' {
            if d.len > 2 && d[2] == 'O' {
                abort("staged");
            }
        }
    }
}

thread_fn target() { fuzz::call(staged); }

// Remove the files of a directory, then the directory.
fn remove_dir_files(dir: const u8[:]) {
    var names: u8[>..] = [];
    if !list_dir(dir, names) {
        return;
    }
    var pos: i64 = 0;
    while pos < names.len {
        var stop = find(names[pos..names.len], "\n");
        if stop < 0 {
            stop = names.len - pos;
        }
        if stop > 0 {
            var file: u8[>..] = [];
            file.append(dir);
            file.append("/");
            file.append(names[pos..pos + stop]);
            delete_file(file);
        }
        pos += stop + 1;
    }
    delete_dir(dir);
}

// Remove the files that the example made, then the directories.
fn clean(corpus: const u8[:], crashers: const u8[:], name: const u8[:]) {
    var c: u8[>..] = [];
    c.append(corpus);
    c.append("/");
    c.append(name);
    remove_dir_files(c);
    remove_dir_files(corpus);
    var k: u8[>..] = [];
    k.append(crashers);
    k.append("/");
    k.append(name);
    remove_dir_files(k);
    remove_dir_files(crashers);
}

fn main() {
    var path: u8[>..] = [];
    if fuzz::coverage_path(path) {
        print("coverage compiler: ", path);
    }
    var cfg = fuzz::config();
    cfg.seed = 1;
    cfg.runs = 20000;
    cfg.max_len = 16;
    // Keep the files of this example in the scratch directory.
    var scratch: u8[>..] = [];
    env("TMPDIR", scratch);
    if scratch.len == 0 {
        scratch.append(".");
    }
    var crashers: u8[>..] = [];
    crashers.append(scratch);
    crashers.append("/coverage-example-crashers");
    var corpus: u8[>..] = [];
    corpus.append(scratch);
    corpus.append("/coverage-example-corpus");
    // A corpus of an earlier run would seed this run. Start from none.
    clean(corpus, crashers, "coverage");
    cfg.crash_root.append(crashers);
    cfg.corpus_root.append(corpus);
    var rep = fuzz::Report { };
    let found = fuzz::run("coverage", cfg, rep, target);
    var out: u8[>..] = [];
    fuzz::format_report(out, rep);
    print(out);
    if fuzz::cov_live() {
        print("coverage build: the run found ", found, " abort");
    } else {
        print("plain build: the run found ", found, " abort. Build with the coverage compiler.");
    }
    // The example leaves no file behind.
    clean(corpus, crashers, "coverage");
    return 0;
}
