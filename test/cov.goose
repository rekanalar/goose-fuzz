// The coverage test of the fuzz package.
//
// Build and run: goose build --debug test/cov.goose -o <file>, then run <file>.
// Build it with GOOSE_CC set to the cov-cc script of the package for a
// coverage build. Without the script the program has no coverage, and the
// test checks that the run then behaves as a plain run.
//
// The program prints "live" when the coverage works and "off" when it does
// not. The gate reads that word.

import std;
import os;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "..";

// The branch that only the seed "*" reaches.
fn branch(d: const u8[:]) {
    if d.len > 0 && d[0] == 42 {
        var sum: i64 = 0;
        for i in 0..d.len {
            sum += d[i] as i64;
        }
        if sum == 0 {
            abort("unreachable");
        }
    }
}

thread_fn branch_target() { fuzz::call(branch); }

// A target with three stages. Each stage opens only for one byte, so a
// blind mutator seldom reaches the abort. The coverage shows each stage
// as new code, and the run keeps the input that opened it.
fn staged(d: const u8[:]) {
    if d.len > 0 && d[0] == 'G' {
        if d.len > 1 && d[1] == 'O' {
            if d.len > 2 && d[2] == 'O' {
                abort("staged");
            }
        }
    }
}

thread_fn staged_target() { fuzz::call(staged); }

fn scratch(name: const u8[:], out: u8[>..]&) {
    env("TMPDIR", out);
    out.append("/");
    out.append(name);
}

// Remove the files of a directory, then the directory.
fn clean_dir(dir: const u8[:]) {
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
            var path: u8[>..] = [];
            path.append(dir);
            path.append("/");
            path.append(names[pos..pos + stop]);
            delete_file(path);
        }
        pos += stop + 1;
    }
    delete_dir(dir);
}

// The number of files in a directory.
fn count_files(dir: const u8[:]) -> i64 {
    var names: u8[>..] = [];
    if !list_dir(dir, names) {
        return 0;
    }
    var n: i64 = 0;
    var pos: i64 = 0;
    while pos < names.len {
        var stop = find(names[pos..names.len], "\n");
        if stop < 0 {
            stop = names.len - pos;
        }
        if stop > 0 {
            n += 1;
        }
        pos += stop + 1;
    }
    return n;
}

// Remove the directories that the test makes, deepest first. clean_dir
// takes the files of one directory only.
fn wipe(root: const u8[:]) {
    let subs: const u8[:][18] = ["/seeds", "/corpus/cov", "/corpus", "/corpus2/det", "/corpus2",
        "/corpus3/same", "/corpus3", "/corpus4/staged", "/corpus4", "/corpus5/cap", "/corpus5", "/crashers/cov", "/crashers/det",
        "/crashers/same", "/crashers/staged", "/crashers/cap", "/crashers", ""];
    for s in subs {
        var path: u8[>..] = [];
        path.append(root);
        path.append(s);
        clean_dir(path);
    }
}

fn main() {
    var root: u8[>..] = [];
    scratch("fuzz-cov-test", root);
    wipe(root);
    make_dir(root);

    var seeds: u8[>..] = [];
    seeds.append(root);
    seeds.append("/seeds");
    make_dir(seeds);
    var p1: u8[>..] = [];
    p1.append(seeds);
    p1.append("/a");
    assert(write_file(p1, "a"));
    var p2: u8[>..] = [];
    p2.append(seeds);
    p2.append("/b");
    assert(write_file(p2, "*"));

    var croot: u8[>..] = [];
    croot.append(root);
    croot.append("/corpus");

    var cfg = fuzz::config();
    cfg.seed = 7;
    cfg.runs = 0;
    cfg.seed_dir.append(seeds);
    cfg.corpus_root.append(croot);
    cfg.crash_root.append(root);
    cfg.crash_root.append("/crashers");

    var rep = fuzz::Report { };
    assert(fuzz::run("cov", cfg, rep, branch_target) == 0);
    // Each seed ran once.
    assert(rep.runs == 2);

    // The path of the wrapper names a file, or the path is not available
    // when the package sits in an odd place. A coverage build needs it.
    var script: u8[>..] = [];
    let have_script = fuzz::coverage_path(script);

    var star: u8[>..] = [];
    star.append(croot);
    star.append("/cov/");
    fuzz::hex16(star, fuzz::fnv1a64("*"));

    var text: u8[>..] = [];
    fuzz::format_report(text, rep);

    if fuzz::cov_live() {
        print("live");
        assert(have_script);
        assert(file_exists(script));
        // The first input reaches edges that are all new. The seed "*"
        // reaches the branch, so it is interesting too.
        assert(rep.edges > 0);
        assert(rep.interesting >= 2);
        assert(file_exists(star));
        assert(find(text, "edges: ") >= 0);
        assert(find(text, "interesting: ") >= 0);

        // The coverage belongs to one run. The second run empties the table,
        // so it finds the inputs interesting again, and the corpus files of
        // the first run are seeds of it.
        var rep2 = fuzz::Report { };
        assert(fuzz::run("cov", cfg, rep2, branch_target) == 0);
        // Two seeds and the corpus files of the first run.
        assert(rep2.runs > rep.runs);
        assert(rep2.interesting >= 1);
        assert(rep2.edges > 0);

        // The control: two seeds that take the same path. Only the first
        // reaches new code, so exactly one input is interesting.
        var same: u8[>..] = [];
        same.append(root);
        same.append("/seeds");
        assert(delete_file(p2));
        assert(write_file(p2, "b"));
        var cfg3 = fuzz::config();
        cfg3.seed = 7;
        cfg3.runs = 0;
        cfg3.seed_dir.append(same);
        cfg3.corpus_root.append(root);
        cfg3.corpus_root.append("/corpus3");
        cfg3.crash_root.append(root);
        cfg3.crash_root.append("/crashers");
        var rep3 = fuzz::Report { };
        assert(fuzz::run("same", cfg3, rep3, branch_target) == 0);
        assert(rep3.runs == 2);
        assert(rep3.interesting == 1);

        // The guidance finds what a blind run does not. With the seed 1
        // and 20000 runs the run opens all three stages. The coverage
        // decides this by the first sight of an address, so the result
        // does not depend on the compiler or on the load address. On
        // eight seeds the guided run found the abort seven times, and a
        // blind run found it never.
        var cfg4 = fuzz::config();
        cfg4.seed = 1;
        cfg4.runs = 20000;
        cfg4.max_len = 16;
        cfg4.corpus_root.append(root);
        cfg4.corpus_root.append("/corpus4");
        cfg4.crash_root.append(root);
        cfg4.crash_root.append("/crashers");
        var rep4 = fuzz::Report { };
        assert(fuzz::run("staged", cfg4, rep4, staged_target) == 1);
        assert(rep4.interesting > 3);

        // The cap of the corpus. A directory that holds 4096 files takes no
        // more. The first input of a run is interesting, so the run tries
        // to save it. It turns the input away and counts it.
        var capdir: u8[>..] = [];
        capdir.append(root);
        capdir.append("/corpus5");
        make_dir(capdir);
        capdir.append("/cap");
        make_dir(capdir);
        for k in 0..4096 {
            var f: u8[>..] = [];
            f.append(capdir);
            f.append("/f");
            format_int(f, k, 10, 0, ' ');
            assert(write_file(f, "x"));
        }
        assert(count_files(capdir) == 4096);
        var cfg5 = fuzz::config();
        cfg5.seed = 2;
        cfg5.runs = 0;
        cfg5.corpus_root.append(root);
        cfg5.corpus_root.append("/corpus5");
        cfg5.crash_root.append(root);
        cfg5.crash_root.append("/crashers");
        var rep5 = fuzz::Report { };
        assert(fuzz::run("cap", cfg5, rep5, branch_target) == 0);
        assert(rep5.corpus_dropped > 0);
        assert(count_files(capdir) == 4096);
    } else {
        print("off");
        // A build without the coverage flag behaves as before.
        assert(rep.edges == 0);
        assert(rep.interesting == 0);
        assert(rep.corpus_dropped == 0);
        assert(!file_exists(star));
        assert(find(text, "edges") < 0);
        assert(find(text, "interesting") < 0);
        assert(find(text, "seed: ") == 0);
    }

    // The same seed and the same build give the same report.
    cfg.corpus_root.clear();
    cfg.corpus_root.append(root);
    cfg.corpus_root.append("/corpus2");
    var a = fuzz::Report { };
    var b = fuzz::Report { };
    assert(fuzz::run("det", cfg, a, branch_target) == 0);
    clean_dir(croot);
    var c2: u8[>..] = [];
    c2.append(root);
    c2.append("/corpus2/det");
    clean_dir(c2);
    assert(fuzz::run("det", cfg, b, branch_target) == 0);
    assert(a.runs == b.runs);
    assert(a.interesting == b.interesting);

    wipe(root);
    print("cov test passed");
    return 0;
}
