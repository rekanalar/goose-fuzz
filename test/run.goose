// Tests for the fuzz package.
//
// Build and run: goose build --debug test/run.goose -o <file>, then run <file>.
// The tests start worker threads, so "goose run" cannot run them.

import std;
import os;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "..";
import targets;

fn check_hash(data: const u8[:], want: const u8[:]) {
    var out: u8[>..] = [];
    fuzz::hex16(out, fuzz::fnv1a64(data));
    assert(out == want);
}

fn test_hash() {
    // The published FNV-1a 64-bit test values.
    check_hash("", "cbf29ce484222325");
    check_hash("a", "af63dc4c8601ec8c");
    check_hash("foobar", "85944171f73967e8");
    var out: u8[>..] = [];
    fuzz::hex16(out, 1);
    assert(out == "0000000000000001");
}

fn check_site(msg: const u8[:], want: const u8[:]) {
    var out: u8[>..] = [];
    fuzz::site_of(msg, out);
    assert(out == want);
}

fn test_site() {
    check_site("assert failed (c.goose:5)", "c.goose:5");
    check_site("index 13 out of bounds (length 3) (t.goose:9)", "t.goose:9");
    check_site("division by zero (t.goose:10)", "t.goose:10");
    check_site("integer overflow (debug): 2147483647 + 3 at i32 (t.goose:11)", "t.goose:11");
    check_site("boom", "unknown");
    check_site("", "unknown");
    check_site("odd (length 3)", "unknown");
    check_site("odd (a:b)", "unknown");
}

fn test_report() {
    var rep = fuzz::Report { };
    assert(rep.runs == 0 && rep.dropped == 0 && rep.save_failed == 0);
    assert(fuzz::finding_count(rep) == 0);
    let i = fuzz::record(rep, "a.goose:1", "boom", "xyz");
    assert(i == 0);
    assert(fuzz::finding_site(rep, 0) == "a.goose:1");
    assert(fuzz::finding_message(rep, 0) == "boom");
    assert(fuzz::finding_input(rep, 0) == "xyz");
    assert(fuzz::finding_hits(rep, 0) == 1);
    // a known site adds a hit and no finding
    assert(fuzz::record(rep, "a.goose:1", "other", "q") == 0);
    assert(fuzz::finding_count(rep) == 1);
    assert(fuzz::finding_hits(rep, 0) == 2);
    assert(fuzz::finding_message(rep, 0) == "boom");
    // 300 more distinct sites: 255 fit (256 in all), 45 more drop... count exactly
    for k in 0..300 {
        var site: u8[>..] = [];
        site.append("s.goose:");
        format_int(site, k, 10, 0, ' ');
        fuzz::record(rep, site, "m", "i");
    }
    assert(fuzz::finding_count(rep) == 256);
    assert(rep.dropped == 45);
}

fn test_exec() {
    var why: u8[>..] = [];
    assert(fuzz::run_one("", why, targets::ok_target));
    why.clear();
    assert(!fuzz::run_one("\x07", why, targets::assert_target));
    assert(find(why, "assert failed") >= 0);
    why.clear();
    assert(!fuzz::run_one("\xc8", why, targets::index_target));
    assert(find(why, "out of bounds") >= 0);
    why.clear();
    assert(!fuzz::run_one("\x09", why, targets::div_target));
    assert(find(why, "division by zero") >= 0);
    why.clear();
    assert(!fuzz::run_one("\xc8", why, targets::overflow_target));
    assert(find(why, "overflow") >= 0);
    why.clear();
    // the worker may not read its input: no stale input may reach later runs
    assert(!fuzz::run_one("\x07", why, targets::assert_target));
    why.clear();
    for i in 0..200 {
        assert(fuzz::run_one("\x01", why, targets::ok_target));
    }
}

fn seeds16(pool: u8[>..]&, seeds: fuzz::Seed[>..]&) {
    for i in 0..16 {
        pool.push(i as u8);
    }
    var s = fuzz::Seed { };
    s.off = 0;
    s.len = 16;
    s.energy = 5;
    s.hits = 0;
    seeds.push(s);
}

fn test_mutate() {
    var pool: u8[>..] = [];
    var seeds: fuzz::Seed[>..] = [];
    seeds16(pool, seeds);
    var r = rng { 1 };
    var seen: i64[20] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    var out: u8[>..] = [];
    var src: i64 = -1;
    for i in 0..20000 {
        out.clear();
        let k = fuzz::mutate_next(r, pool, seeds, 16, 0, out, src);
        assert(out.len <= 16);
        assert(src == 0);
        seen[k] += 1;
    }
    // The eighteen byte kinds: 0 to 3 and 6 to 19. The kinds 4 and 5
    // belong to the dictionary path.
    for k in 0..4 {
        assert(seen[k] > 0);
    }
    for k in 6..20 {
        assert(seen[k] > 0);
    }
    assert(seen[4] == 0 && seen[5] == 0);
    // the same seed gives the same inputs
    var a: u8[>..] = [];
    var b: u8[>..] = [];
    var ra = rng { 7 };
    var rb = rng { 7 };
    for i in 0..100 {
        out.clear();
        fuzz::mutate_next(ra, pool, seeds, 16, 0, out, src);
        a.append(out);
        out.clear();
        fuzz::mutate_next(rb, pool, seeds, 16, 0, out, src);
        b.append(out);
    }
    assert(a == b);
    // no seeds: starts from the empty input
    var empty: fuzz::Seed[>..] = [];
    var nopool: u8[>..] = [];
    for i in 0..100 {
        out.clear();
        fuzz::mutate_next(ra, nopool, empty, 4, 0, out, src);
        assert(out.len <= 4);
        assert(src == -1);
    }
}

// The first 8 inputs of seed 1, recorded on v2026.3 and equal on v2026.4.
// The pinned bytes of the first 8 inputs of seed 1. The run fills the
// value in, and the value stays equal on both compiler versions.
const MUTATE_TABLE = "";

fn test_mutate_table() {
    var pool: u8[>..] = [];
    var seeds: fuzz::Seed[>..] = [];
    seeds16(pool, seeds);
    var r = rng { 1 };
    var out: u8[>..] = [];
    var all: u8[>..] = [];
    var src: i64 = -1;
    for n in 0..8 {
        out.clear();
        fuzz::mutate_next(r, pool, seeds, 16, 0, out, src);
        for b in out {
            format_uint(all, b, 16, 2, '0');
        }
        all.push('/');
    }
    assert(all == "000102030405060008090a0b0c0d0e0f/000102030405060708800a0b0c0d0e0f/00060708090a0b0c0d0e010203040506/000102030405060708090a0b0c0d0e0f/000102030405060708090b0c0d0e0f/000102030405060708090af40c0d0e0f/0a0b0c0d0e0f00010203040506070809/000102030405060708090a0b0c0d0e06/");
}

// A scratch directory under TMPDIR for one test.
fn scratch(name: const u8[:], out: u8[>..]&) {
    env("TMPDIR", out);
    assert(out.len > 0);
    out.append("/");
    out.append(name);
    make_dir(out);
}

fn test_corpus() {
    var dir: u8[>..] = [];
    scratch("fz-seeds", dir);
    var pa: u8[>..] = [];
    pa.append(dir);
    pa.append("/a");
    var pb: u8[>..] = [];
    pb.append(dir);
    pb.append("/b");
    assert(write_file(pb, "0123456789"));
    assert(write_file(pa, "xy"));
    var pool: u8[>..] = [];
    var ends: i64[>..] = [];
    var seeds: fuzz::Seed[>..] = [];
    assert(fuzz::load_seeds(dir, 4, 9, pool, seeds) == 2);
    assert(pool == "xy0123");
    assert(seeds.len == 2);
    assert(seeds[0].off == 0 && seeds[0].len == 2 && seeds[0].energy == 9);
    assert(seeds[1].off == 2 && seeds[1].len == 4 && seeds[1].energy == 9);
    delete_file(pa);
    delete_file(pb);
    delete_dir(dir);
    var pool2: u8[>..] = [];
    var seeds2: fuzz::Seed[>..] = [];
    assert(fuzz::load_seeds(dir, 4, 9, pool2, seeds2) == -1);
}

fn test_run() {
    var cfg = fuzz::config();
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-run-root");
    cfg.crash_root.append(root);
    cfg.seed = 5;
    cfg.runs = 1000;
    var rep = fuzz::Report { };
    assert(fuzz::run("ok", cfg, rep, targets::ok_target) == 0);
    assert(rep.runs == 1000);
    assert(rep.seed == 5);
    // The planted assert at targets.goose:14 runs with ten fixed seeds.
    cfg.runs = 10000;
    for sd in 1..11 {
        cfg.seed = sd as u64;
        var r2 = fuzz::Report { };
        assert(fuzz::run("assert", cfg, r2, targets::assert_target) == 1);
        assert(fuzz::finding_site(r2, 0) == "test/targets.goose:14");
        assert(find(fuzz::finding_message(r2, 0), "assert failed") >= 0);
    }
    // two sites
    var r3 = fuzz::Report { };
    assert(fuzz::run("two", cfg, r3, targets::two_target) == 2);
    // one site, many hits
    cfg.runs = 500;
    var r4 = fuzz::Report { };
    assert(fuzz::run("always", cfg, r4, targets::always_target) == 1);
    assert(fuzz::finding_hits(r4, 0) == 500);
    // seed 0 picks a nonzero seed
    cfg.seed = 0;
    cfg.runs = 10;
    var r5 = fuzz::Report { };
    fuzz::run("ok", cfg, r5, targets::ok_target);
    assert(r5.seed != 0);
    // a missing seed directory makes run return -1 and run nothing
    cfg.seed_dir.append("no/such/dir");
    var r6 = fuzz::Report { };
    assert(fuzz::run("ok", cfg, r6, targets::ok_target) == -1);
    assert(r6.runs == 0);
    // seed 1, 10000 runs: recorded on v2026.3 and equal on v2026.4
    cfg.seed = 1;
    cfg.runs = 10000;
    cfg.seed_dir.clear();
    var r7 = fuzz::Report { };
    assert(fuzz::run("assert", cfg, r7, targets::assert_target) == 1);
    assert(r7.runs == 10000 && fuzz::finding_hits(r7, 0) == 31);
    for n in ["always", "assert", "two"] {
        var d: u8[>..] = [];
        d.append(root);
        d.append("/");
        d.append(n);
        clean_dir(d);
    }
    delete_dir(root);
    // report text
    var txt: u8[>..] = [];
    fuzz::format_report(txt, r4);
    assert(find(txt, "test/targets.goose:") >= 0);
}

// Delete every file of dir, then dir.
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
            var p: u8[>..] = [];
            p.append(dir);
            p.append("/");
            p.append(names[pos..pos + stop]);
            delete_file(p);
        }
        pos += stop + 1;
    }
    delete_dir(dir);
}

fn test_crashers() {
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-crash-root");
    var sub: u8[>..] = [];
    sub.append(root);
    sub.append("/assert");
    clean_dir(sub);
    delete_dir(root);
    var cfg = fuzz::config();
    cfg.seed = 1;
    cfg.runs = 10000;
    cfg.crash_root.append(root);
    var rep = fuzz::Report { };
    assert(fuzz::run("assert", cfg, rep, targets::assert_target) == 1);
    assert(rep.save_failed == 0 && rep.findings[0].saved);
    // one file, named by the hash of its bytes
    var names: u8[>..] = [];
    assert(list_dir(sub, names));
    var want: u8[>..] = [];
    fuzz::hex16(want, fuzz::fnv1a64(fuzz::finding_input(rep, 0)));
    want.append("\n");
    assert(names == want);
    // a second run saves no second file
    var rep2 = fuzz::Report { };
    assert(fuzz::run("assert", cfg, rep2, targets::assert_target) == 1);
    var names2: u8[>..] = [];
    assert(list_dir(sub, names2));
    assert(names2 == want);
    // replay: the abort still happens, then it is gone
    var rr = fuzz::Report { };
    // passed files = rr.runs - result
    assert(fuzz::replay("assert", root, rr, targets::assert_target) == 1);
    assert(rr.runs == 1 && fuzz::finding_count(rr) == 1);
    var rr2 = fuzz::Report { };
    assert(fuzz::replay("assert", root, rr2, targets::ok_target) == 0);
    assert(rr2.runs == 1 && fuzz::finding_count(rr2) == 0);
    var rr3 = fuzz::Report { };
    assert(fuzz::replay("nothing", root, rr3, targets::assert_target) == 0);
    clean_dir(sub);
    delete_dir(root);
    // an unwritable root keeps the finding: a directory cannot sit under a file
    var blocker: u8[>..] = [];
    env("TMPDIR", blocker);
    blocker.append("/fz-not-a-dir");
    assert(write_file(blocker, "x"));
    var bad = fuzz::config();
    bad.seed = 1;
    bad.runs = 10000;
    bad.crash_root.append(blocker);
    bad.crash_root.append("/root");
    var rb = fuzz::Report { };
    assert(fuzz::run("assert", bad, rb, targets::assert_target) == 1);
    assert(!rb.findings[0].saved && rb.save_failed == 1);
    delete_file(blocker);
}

fn test_shrink() {
    var big: u8[>..] = [];
    big.resize(4000, 85);
    big[0] = 3;
    big[1] = 1;
    big[2] = 4;
    var out: u8[>..] = [];
    assert(fuzz::shrink(big, out, targets::prefix_target));
    assert(out.len == 3 && out[0] == 3 && out[1] == 1 && out[2] == 4);
    // an input that does not abort: false, out unchanged
    var keep: u8[>..] = [];
    keep.append("keep");
    assert(!fuzz::shrink("xyz", keep, targets::prefix_target));
    assert(keep == "keep");
    // a shorter input that aborts at another site is refused
    var two: u8[>..] = [1, 2, 2];
    var o2: u8[>..] = [];
    assert(fuzz::shrink(two, o2, targets::two_target));
    assert(o2.len == 1 && o2[0] == 1);
}

fn test_law() {
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-law-root");
    var cfg = fuzz::config();
    cfg.seed = 1;
    cfg.runs = 10000;
    cfg.crash_root.append(root);
    var ok = fuzz::Report { };
    assert(fuzz::run("law", cfg, ok, targets::law_true_target) == 0);
    var bad = fuzz::Report { };
    assert(fuzz::run("law", cfg, bad, targets::law_nine_target) == 1);
    assert(find(fuzz::finding_message(bad, 0), "law failed") >= 0);
    assert(bad.findings[0].saved);
    var d: u8[>..] = [];
    d.append(root);
    d.append("/law");
    clean_dir(d);
    delete_dir(root);
}

fn test_kinds() {
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-kinds-root");
    var cfg = fuzz::config();
    cfg.seed = 1;
    cfg.runs = 10000;
    cfg.crash_root.append(root);
    var a = fuzz::Report { };
    assert(fuzz::run("index", cfg, a, targets::index_target) == 1);
    assert(find(fuzz::finding_message(a, 0), "out of bounds") >= 0);
    var b = fuzz::Report { };
    assert(fuzz::run("div", cfg, b, targets::div_target) == 1);
    assert(find(fuzz::finding_message(b, 0), "division by zero") >= 0);
    var c = fuzz::Report { };
    assert(fuzz::run("overflow", cfg, c, targets::overflow_target) == 1);
    assert(find(fuzz::finding_message(c, 0), "overflow") >= 0);
    for n in ["index", "div", "overflow"] {
        var d: u8[>..] = [];
        d.append(root);
        d.append("/");
        d.append(n);
        clean_dir(d);
    }
    delete_dir(root);
}

fn test_limits() {
    var root: u8[>..] = [];
    env("TMPDIR", root);
    var cfg = fuzz::config();
    assert(cfg.runs == 10000 && cfg.time_ms == 0 && cfg.max_len == 4096);
    cfg.seed = 3;
    cfg.runs = 500;
    var r = fuzz::Report { };
    fuzz::run("ok", cfg, r, targets::ok_target);
    assert(r.runs == 500);
    // the time limit ends a long run
    cfg.runs = 1000000000;
    cfg.time_ms = 300;
    let t0 = clock_ns();
    var r2 = fuzz::Report { };
    fuzz::run("ok", cfg, r2, targets::ok_target);
    let ms = (clock_ns() - t0) / 1000000;
    assert(ms >= 300 && ms < 1500);
    assert(r2.runs > 0 && r2.runs < 1000000000);
    // both limits: the first one ends the run
    cfg.runs = 5;
    cfg.time_ms = 100000;
    var r3 = fuzz::Report { };
    fuzz::run("ok", cfg, r3, targets::ok_target);
    assert(r3.runs == 5);
    // runs 0 runs the seeds once: two seed files, two runs
    var dir: u8[>..] = [];
    scratch("fz-limit-seeds", dir);
    var pa: u8[>..] = [];
    pa.append(dir);
    pa.append("/a");
    var pb: u8[>..] = [];
    pb.append(dir);
    pb.append("/b");
    write_file(pa, "x");
    write_file(pb, "y");
    cfg.runs = 0;
    cfg.time_ms = 0;
    cfg.seed_dir.append(dir);
    var r4 = fuzz::Report { };
    fuzz::run("ok", cfg, r4, targets::ok_target);
    assert(r4.runs == 2);
    clean_dir(dir);
}

// The coverage fields hold in a plain build and in a coverage build. A
// program without the coverage flag finds nothing interesting, writes no
// corpus file, and names no coverage in its report. The same run of two
// programs gives the same inputs.
fn test_coverage_fields() {
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fuzz-run-cov");
    var croot: u8[>..] = [];
    croot.append(root);
    croot.append("/corpus");
    var cfg = fuzz::config();
    cfg.seed = 3;
    cfg.runs = 50;
    cfg.corpus_root.append(croot);
    cfg.crash_root.append(root);
    cfg.crash_root.append("/crashers");
    var rep = fuzz::Report { };
    assert(fuzz::run("ok-cov", cfg, rep, targets::ok_target) == 0);
    assert(rep.runs == 50);
    assert(rep.interesting <= rep.runs);
    assert(rep.corpus_dropped == 0);
    var text: u8[>..] = [];
    fuzz::format_report(text, rep);
    if !fuzz::cov_live() {
        assert(rep.edges == 0 && rep.interesting == 0);
        assert(find(text, "edges") < 0);
        var dir: u8[>..] = [];
        fuzz::corpus_dir(croot, "ok-cov", dir);
        assert(!is_dir(dir));
    } else {
        assert(find(text, "edges: ") >= 0);
    }
    // The corpus directory defaults to fuzz/corpus.
    var d: u8[>..] = [];
    fuzz::corpus_dir("", "n", d);
    assert(d == "fuzz/corpus/n");
    var d2: u8[>..] = [];
    fuzz::corpus_dir("x", "n", d2);
    assert(d2 == "x/n");
    var sub: u8[>..] = [];
    sub.append(croot);
    sub.append("/ok-cov");
    clean_dir(sub);
    delete_dir(croot);
    delete_dir(root);
}

fn main() {
    if fuzz::is_child() {
        // A built binary takes its exit code from exit, not from the
        // return of main. The name is the seventh argument after the
        // marker, so one binary serves every target of the suite. A
        // parent that holds a dictionary passes a file in the eighth
        // argument, so the dict target runs then.
        let a = args();
        let mark = fuzz::marker_index();
        let name = a[mark + 7];
        var code: i32 = 0;
        if mark >= 0 && a.len >= mark + 9 && a[mark + 8].len > 0 {
            code = fuzz::child_batch(targets::goose_target);
        } else if name == "exit-child" {
            code = fuzz::child_batch(targets::exit_target);
        } else if name == "hang-child" {
            code = fuzz::child_batch(targets::hang_target);
        } else if name == "slow-child" {
            code = fuzz::child_batch(targets::slow_target);
        } else if name == "slow12-child" {
            code = fuzz::child_batch(targets::slow12_target);
        } else {
            code = fuzz::child_batch(targets::ok_target);
        }
        exit(code);
    }
    test_hash();
    test_site();
    test_report();
    test_exec();
    test_mutate();
    test_mutate_table();
    test_corpus();
    test_run();
    test_crashers();
    test_shrink();
    test_law();
    test_kinds();
    test_limits();
    test_dict();
    test_dict_run();
    test_dict_child();
    test_reader();
    test_coverage_fields();
    test_typed();
    test_parallel();
    test_speedup();
    test_pool();
    test_score();
    test_run_with();
    test_probe();
    test_child();
    print("ok hash, site, report, exec, mutate, child, dict, reader, typed, parallel");
    return 0;
}

// The pool: a seed that finds nothing loses its energy and leaves it.
// The order that takes the best seed first runs clean too.
fn test_pool() {
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-pool-root");
    clean_dir(root);
    make_dir(root);
    var dir: u8[>..] = [];
    dir.append(root);
    dir.append("/seeds");
    make_dir(dir);
    var pa: u8[>..] = [];
    pa.append(dir);
    pa.append("/a");
    var pb: u8[>..] = [];
    pb.append(dir);
    pb.append("/b");
    assert(write_file(pa, "xx"));
    assert(write_file(pb, "yy"));

    var cfg = fuzz::config();
    cfg.crash_root.append(root);
    cfg.seed = 5;
    cfg.runs = 300;
    cfg.seed_energy = 5;
    cfg.seed_dir.append(dir);
    var rep = fuzz::Report { };
    assert(fuzz::run("ok", cfg, rep, targets::ok_target) == 0);
    assert(rep.runs == 300);
    assert(rep.seeds_retired >= 2);

    var cfg2 = fuzz::config();
    cfg2.crash_root.append(root);
    cfg2.seed = 6;
    cfg2.runs = 100;
    cfg2.pool_order = 1;
    cfg2.seed_dir.append(dir);
    var rep2 = fuzz::Report { };
    assert(fuzz::run("ok", cfg2, rep2, targets::ok_target) == 0);
    assert(rep2.runs == 100);

    clean_dir(root);
    delete_dir(root);
}

// The score of the target steers the run, and the time of the run does
// too.
fn test_score() {
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-score-root");
    clean_dir(root);
    make_dir(root);
    var cfg = fuzz::config();
    cfg.crash_root.append(root);
    cfg.seed = 3;
    cfg.runs = 200;
    cfg.score_mode = 1;
    var rep = fuzz::Report { };
    assert(fuzz::run("ok", cfg, rep, targets::score_target) == 0);
    assert(rep.best_score > 0.0);
    assert(fuzz::best_input(rep).len == rep.best_score as i64);
    cfg.score_mode = 2;
    cfg.runs = 50;
    var rep2 = fuzz::Report { };
    assert(fuzz::run("ok", cfg, rep2, targets::ok_target) == 0);
    assert(rep2.best_score > 0.0);
    // With the mode off, a scoring target leaves no score and no queue.
    cfg.score_mode = 0;
    cfg.runs = 20;
    var rep3 = fuzz::Report { };
    assert(fuzz::run("ok", cfg, rep3, targets::score_target) == 0);
    assert(rep3.best_score == 0.0 && fuzz::best_input(rep3).len == 0);
    assert(fuzz::poll_score() == 0.0);
    clean_dir(root);
    delete_dir(root);
}

// The mutator of the caller. A mutator that writes finds the mark, a
// mutator that refuses falls back to the kinds of the table, and a long
// input is cut to the limit.
fn mark_mutator(data: const u8[:], out: u8[>..]&) -> bool {
    out.append(data);
    for i in 0..8 {
        out.push(250);
    }
    return true;
}

fn idle_mutator(data: const u8[:], out: u8[>..]&) -> bool {
    if data.len > 0 {
        return false;
    }
    return false;
}

fn long_mutator(data: const u8[:], out: u8[>..]&) -> bool {
    for i in 0..5000 {
        out.push(65);
    }
    return true;
}

fn test_run_with() {
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-with-root");
    clean_dir(root);
    var cfg = fuzz::config();
    cfg.crash_root.append(root);
    cfg.seed = 11;
    cfg.runs = 300;
    cfg.mutator_rate = 100;
    var rep = fuzz::Report { };
    assert(fuzz::run_with("mark", cfg, rep, targets::mark_target, mark_mutator) == 1);
    // The kinds of the table hold no count: the mutator made every
    // input.
    var sum: i64 = 0;
    for k in 0..20 {
        sum += rep.kind_count[k];
    }
    assert(sum == 0);

    var cfg2 = fuzz::config();
    cfg2.crash_root.append(root);
    cfg2.seed = 12;
    cfg2.runs = 100;
    cfg2.mutator_rate = 100;
    var rep2 = fuzz::Report { };
    assert(fuzz::run_with("ok", cfg2, rep2, targets::ok_target, idle_mutator) == 0);
    var sum2: i64 = 0;
    for k in 0..20 {
        sum2 += rep2.kind_count[k];
    }
    assert(sum2 > 0);

    var cfg3 = fuzz::config();
    cfg3.crash_root.append(root);
    cfg3.seed = 13;
    cfg3.runs = 50;
    cfg3.mutator_rate = 100;
    var rep3 = fuzz::Report { };
    assert(fuzz::run_with("len", cfg3, rep3, targets::len_target, long_mutator) == 0);

    clean_dir(root);
    delete_dir(root);
}

// The probe of the parent. A slow input ends the probe, and a hang
// stops the probe again.
fn test_probe() {
    let prog = args()[0];
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-probe-root");
    clean_dir(root);
    var cfg = fuzz::config();
    cfg.crash_root.append(root);
    cfg.child.append(prog);
    cfg.seed = 8;
    cfg.runs = 100;
    var rep = fuzz::Report { };
    assert(fuzz::run_isolated("slow12-child", cfg, rep) == 1);
    assert(fuzz::finding_site(rep, 0) == "child:slow");
    assert(rep.slow >= 1 && rep.slow == fuzz::finding_hits(rep, 0));
    clean_dir(root);
    delete_dir(root);
}

// The child mode: the exit case, the hang case, the clean batch, the
// rate, and the hard errors.
fn test_child() {
    let prog = args()[0];
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-child-root");
    clean_dir(root);

    // One seed file with the exit mark. The first input of the first
    // batch calls exit(3) in the child.
    var sdir: u8[>..] = [];
    sdir.append(root);
    sdir.append("/seeds");
    make_dir(root);
    make_dir(sdir);
    var sp: u8[>..] = [];
    sp.append(sdir);
    sp.append("/m");
    var mark: u8[>..] = [];
    mark.push(61);
    assert(write_file(sp, mark));

    var cfg = fuzz::config();
    cfg.child.append(prog);
    cfg.seed = 1;
    cfg.runs = 100;
    cfg.seed_dir.append(sdir);
    var croot: u8[>..] = [];
    croot.append(root);
    croot.append("/crash");
    cfg.crash_root.append(croot);
    var rep = fuzz::Report { };
    assert(fuzz::run_isolated("exit-child", cfg, rep) == 1);
    assert(rep.runs == 100);
    assert(rep.seed == 1);
    assert(fuzz::finding_site(rep, 0) == "child:exit 3");
    assert(find(fuzz::finding_message(rep, 0), "code 3") >= 0);
    assert(rep.findings[0].saved);
    var names: u8[>..] = [];
    var cdir: u8[>..] = [];
    cdir.append(croot);
    cdir.append("/exit-child");
    assert(list_dir(cdir, names));
    assert(names.len > 0);

    // The hang case. The child sleeps 30 seconds, the parent stops it at
    // the limit. The probe of two seconds stops again, so the finding
    // keeps the site of the stop.
    var mark2: u8[>..] = [];
    mark2.push(62);
    assert(write_file(sp, mark2));
    cfg.probe_ms = 2000;
    var rep2 = fuzz::Report { };
    assert(fuzz::run_isolated("hang-child", cfg, rep2) == 1);
    assert(rep2.runs == 100);
    assert(fuzz::finding_site(rep2, 0) == "child:stopped");
    assert(rep2.findings[0].saved);

    // The clean batch and the rate. No seeds, no mark, 2000 inputs.
    var clean = fuzz::config();
    clean.child.append(prog);
    clean.seed = 1;
    clean.runs = 2000;
    var rep3 = fuzz::Report { };
    let t0 = clock_ns();
    assert(fuzz::run_isolated("ok-child", clean, rep3) == 0);
    let ms = (clock_ns() - t0) / 1000000;
    assert(rep3.runs == 2000);
    assert(ms > 0);
    let rate = 2000000 / ms;
    print("child rate: ", rate, " a second");
    assert(rate >= 200);

    // An empty child name is refused.
    var none = fuzz::config();
    none.seed = 1;
    none.runs = 10;
    var rep4 = fuzz::Report { };
    assert(fuzz::run_isolated("ok-child", none, rep4) == -1);
    assert(rep4.runs == 0);

    // A child that does not exist is a hard error.
    var bad = fuzz::config();
    bad.child.append("no-such-child-program-xyz");
    bad.seed = 1;
    bad.runs = 10;
    var rep5 = fuzz::Report { };
    assert(fuzz::run_isolated("ok-child", bad, rep5) == -1);

    clean_dir(root);
    delete_dir(root);
}


// The dictionary: the parser, the loaders, and the reproducibility.
fn test_dict() {
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-dict");
    make_dir(root);
    var path: u8[>..] = [];
    path.append(root);
    path.append("/words.dict");
    var text: u8[>..] = [];
    text.append("# the words\n");
    text.append("\n");
    text.append("alpha=\"GOOSE\"\n");
    text.append("beta=\"A\\\\z\"\n");
    text.append("gamma=\"q\\\"i\"\n");
    text.append("delta=\"\\x00\\xff\"\n");
    assert(write_file(path, text));
    var cfg = fuzz::config();
    var err: u8[>..] = [];
    assert(fuzz::dict_load(cfg, path, err));
    assert(cfg.dict.len > 0);
    // the parsed tokens
    var dpool: u8[>..] = [];
    var dends: i64[>..] = [];
    assert(fuzz::dict_parse(cfg.dict, dpool, dends, err) == 4);
    assert(dends.len == 4);
    assert(fuzz::dict_at(dpool, dends, 0) == "GOOSE");
    assert(fuzz::dict_at(dpool, dends, 1) == "A\\z");
    assert(fuzz::dict_at(dpool, dends, 2) == "q\"i");
    let tok3 = fuzz::dict_at(dpool, dends, 3);
    assert(tok3.len == 2 && tok3[0] == 0 && tok3[1] == 255);
    // a bad line fails the load and names the line
    var bad: u8[>..] = [];
    bad.append("alpha=\"ok\"\n");
    bad.append("\n");
    bad.append("broken\n");
    var bad_path: u8[>..] = [];
    bad_path.append(root);
    bad_path.append("/bad.dict");
    assert(write_file(bad_path, bad));
    var cfg2 = fuzz::config();
    err.clear();
    assert(!fuzz::dict_load(cfg2, bad_path, err));
    assert(find(err, "line 3") >= 0);
    // an unterminated quote names its line
    bad.clear();
    bad.append("x=\"open\n");
    assert(write_file(bad_path, bad));
    err.clear();
    assert(!fuzz::dict_load(cfg2, bad_path, err));
    assert(find(err, "line 1") >= 0);
    // a bad escape names its line
    bad.clear();
    bad.append("x=\"\\q\"\n");
    assert(write_file(bad_path, bad));
    err.clear();
    assert(!fuzz::dict_load(cfg2, bad_path, err));
    assert(find(err, "line 1") >= 0);
    // dict_add appends an escaped line and refuses a full buffer
    var cfg3 = fuzz::config();
    assert(fuzz::dict_add(cfg3, "GO\"OOSE"));
    assert(find(cfg3.dict, "\"GO\\\"OOSE\"") >= 0);
    assert(fuzz::dict_add(cfg3, "\x01"));
    assert(find(cfg3.dict, "\\x01") >= 0);
    var big: u8[>..] = [];
    big.resize(5000, 65);
    var cfg4 = fuzz::config();
    assert(!fuzz::dict_add(cfg4, big));
    // reproducibility with a dictionary: the same seed makes the same inputs
    var pool: u8[>..] = [];
    var seeds: fuzz::Seed[>..] = [];
    seeds16(pool, seeds);
    var dpool2: u8[>..] = [];
    var dends2: i64[>..] = [];
    var derr2: u8[>..] = [];
    assert(fuzz::dict_parse(cfg3.dict, dpool2, dends2, derr2) == 2);
    var a: u8[>..] = [];
    var b: u8[>..] = [];
    var out: u8[>..] = [];
    var ra = rng { 7 };
    var rb = rng { 7 };
    var src: i64 = -1;
    for i in 0..500 {
        out.clear();
        fuzz::mutate_next_dict(ra, pool, seeds, 16, 0, dpool2, dends2, 25, out, src);
        a.append(out);
        out.clear();
        fuzz::mutate_next_dict(rb, pool, seeds, 16, 0, dpool2, dends2, 25, out, src);
        b.append(out);
    }
    assert(a == b);
    // with an empty dictionary the inputs equal those of mutate_next
    var none: u8[>..] = [];
    var noends: i64[>..] = [];
    var a2: u8[>..] = [];
    var b2: u8[>..] = [];
    var ra2 = rng { 3 };
    var rb2 = rng { 3 };
    for i in 0..1000 {
        out.clear();
        fuzz::mutate_next_dict(ra2, pool, seeds, 16, 0, none, noends, 25, out, src);
        a2.append(out);
        out.clear();
        fuzz::mutate_next(rb2, pool, seeds, 16, 0, out, src);
        b2.append(out);
    }
    assert(a2 == b2);
    // token inputs hold the token
    var hits: i64 = 0;
    var rc = rng { 11 };
    for i in 0..2000 {
        out.clear();
        let k = fuzz::mutate_next_dict(rc, pool, seeds, 16, 0, dpool2, dends2, 100, out, src);
        assert(out.len <= 16);
        if k >= 4 {
            hits += 1;
        }
    }
    assert(hits > 400);
    // a token longer than max_len is cut, and no input passes max_len
    var long_dpool: u8[>..] = [];
    var long_dends: i64[>..] = [];
    var long_tok: u8[>..] = [];
    long_tok.resize(64, 65);
    long_dpool.append(long_tok);
    long_dends.push(long_dpool.len);
    var rl = rng { 5 };
    for i in 0..500 {
        out.clear();
        let k = fuzz::mutate_next_dict(rl, pool, seeds, 16, 0, long_dpool, long_dends, 100, out, src);
        assert(out.len <= 16);
        if k == 5 {
            // an overwrite always shows a token byte; the seeds hold only 0 to 15
            assert(find(out, "A") >= 0);
        }
    }
    // a duplicate token stays twice
    var dup_text: u8[>..] = [];
    dup_text.append("a=\"AB\"\n");
    dup_text.append("b=\"AB\"\n");
    var dup_pool: u8[>..] = [];
    var dup_ends: i64[>..] = [];
    var dup_err: u8[>..] = [];
    assert(fuzz::dict_parse(dup_text, dup_pool, dup_ends, dup_err) == 2);
    // a NUL token survives a mutation round as it is
    var nul_text: u8[>..] = [];
    nul_text.append("n=\"\\x00Z\"\n");
    var nul_pool: u8[>..] = [];
    var nul_ends: i64[>..] = [];
    var nul_err: u8[>..] = [];
    assert(fuzz::dict_parse(nul_text, nul_pool, nul_ends, nul_err) == 1);
    var nul_seen = false;
    var rn = rng { 13 };
    for i in 0..500 {
        out.clear();
        fuzz::mutate_next_dict(rn, pool, seeds, 16, 0, nul_pool, nul_ends, 100, out, src);
        if find(out, "\x00Z") >= 0 {
            nul_seen = true;
        }
    }
    assert(nul_seen);
    delete_file(path);
    delete_file(bad_path);
    delete_dir(root);
}

// The token steers the mutator to the prefix abort.
fn test_dict_run() {
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-dict-run");
    make_dir(root);
    var sdir: u8[>..] = [];
    sdir.append(root);
    sdir.append("/seeds");
    make_dir(sdir);
    var names: u8[>..] = [];
    names.append("abc");
    names.append("\nhello\n");
    names.append("xy\n");
    var sp: u8[>..] = [];
    sp.append(sdir);
    sp.append("/m");
    assert(write_file(sp, names));
    var cfg = fuzz::config();
    cfg.seed_dir.append(sdir);
    cfg.runs = 2000;
    var croot: u8[>..] = [];
    croot.append(root);
    croot.append("/crash");
    cfg.crash_root.append(croot);
    // with the word in the dictionary, every run finds the abort
    var dcfg = fuzz::config();
    dcfg.seed_dir.append(sdir);
    dcfg.runs = 2000;
    dcfg.crash_root.append(croot);
    assert(fuzz::dict_add(dcfg, "GOOSE"));
    var found: i64 = 0;
    for s in 1..21 {
        dcfg.seed = s as u64;
        var rep = fuzz::Report { };
        assert(fuzz::run("goose", dcfg, rep, targets::goose_target) == 1);
        found += 1;
    }
    assert(found == 20);
    // without the dictionary, fewer than 10 of the 20 find it
    var plain: i64 = 0;
    for s in 1..21 {
        cfg.seed = s as u64;
        var rep = fuzz::Report { };
        if fuzz::run("goose", cfg, rep, targets::goose_target) == 1 {
            plain += 1;
        }
    }
    assert(plain < 10);
    var d: u8[>..] = [];
    d.append(croot);
    d.append("/goose");
    clean_dir(d);
    clean_dir(sdir);
    delete_dir(root);
}

// The dictionary reaches the child as the eighth and ninth argument.
// A parent that passes seven arguments still runs, as the unchanged
// child tests of v0.2.0 prove.
fn test_dict_child() {
    let prog = args()[0];
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-dict-child");
    make_dir(root);
    var cfg = fuzz::config();
    cfg.child.append(prog);
    cfg.seed = 5;
    cfg.runs = 500;
    cfg.workers = 1;
    var croot: u8[>..] = [];
    croot.append(root);
    croot.append("/crash");
    cfg.crash_root.append(croot);
    assert(fuzz::dict_add(cfg, "GOOSE"));
    var rep = fuzz::Report { };
    assert(fuzz::run_isolated("dict-child", cfg, rep) == 0);
    assert(rep.runs == 500);
    // the child contained the abort and saved the crasher itself
    var cdir: u8[>..] = [];
    cdir.append(croot);
    cdir.append("/dict-child");
    var names: u8[>..] = [];
    assert(list_dir(cdir, names));
    assert(names.len > 0);
    clean_dir(cdir);
    delete_dir(root);
}

// The reader: the ranges, the defaults, and the determinism.
fn test_reader() {
    // the defaults on an empty input
    var r = fuzz::reader("");
    assert(!fuzz::read_bool(r));
    assert(fuzz::read_i64(r, -5, 5) == 0);
    assert(fuzz::read_i64(r, 1000, 1010) == 0);
    assert(fuzz::read_string(r, 8).len == 0);
    assert(fuzz::read_i64_list(r, 4).len == 0);
    // a refused range returns 0 and consumes nothing
    var buf: u8[>..] = [];
    buf.resize(32, 200);
    var r2 = fuzz::reader(buf);
    assert(fuzz::read_i64(r2, 10, 1) == 0);
    assert(r2.pos == 0);
    // every value stays in its range, over random inputs
    var rng1 = rng { 9 };
    var bytes: u8[>..] = [];
    for i in 0..500 {
        bytes.clear();
        let n = rng1.rand_int(33);
        for k in 0..n {
            bytes.push(rng1.rand_int(256) as u8);
        }
        var rr = fuzz::reader(bytes);
        if n == 0 {
            // the defaults of an empty input: false and 0
            assert(!fuzz::read_bool(rr));
            assert(fuzz::read_i64(rr, 1000, 1010) == 0);
            continue;
        }
        let v = fuzz::read_i64(rr, 1000, 1010);
        assert(v >= 1000 && v <= 1010);
        if rr.pos < rr.data.len {
            // bytes remain, so the value maps into the range
            let w = fuzz::read_i64(rr, -7, -3);
            assert(w >= -7 && w <= -3);
        }
        fuzz::read_bool(rr);
        fuzz::read_string(rr, 9);
        fuzz::read_i64_list(rr, 5);
    }
    // the same bytes give the same values twice
    var fixed: u8[>..] = [];
    for i in 0..40 {
        fixed.push(((i * 7 + 3) % 256) as u8);
    }
    var r3 = fuzz::reader(fixed);
    var r4 = fuzz::reader(fixed);
    assert(fuzz::read_i64(r3, 0, 1000000) == fuzz::read_i64(r4, 0, 1000000));
    assert(fuzz::read_bool(r3) == fuzz::read_bool(r4));
    assert(fuzz::read_string(r3, 5) == fuzz::read_string(r4, 5));
    assert(fuzz::read_i64_list(r3, 3) == fuzz::read_i64_list(r4, 3));
    // a list holds what the bytes give, up to the maximum
    var lst: u8[>..] = [];
    lst.push(10);
    for i in 0..40 {
        lst.push(i as u8);
    }
    var r5 = fuzz::reader(lst);
    let xs = fuzz::read_i64_list(r5, 3);
    assert(xs.len == 3);
    var r6 = fuzz::reader(lst);
    let ys = fuzz::read_i64_list(r6, 100);
    assert(ys.len == 5);
    // a short list gives the items that the bytes hold
    var short: u8[>..] = [];
    short.push(4);
    short.push(1);
    short.push(2);
    var r7 = fuzz::reader(short);
    assert(fuzz::read_i64_list(r7, 10).len == 0);
}

// The typed target finds, replays and shrinks.
fn test_typed() {
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-typed");
    make_dir(root);
    // Seed files with several bytes, so an input holds a flag byte too.
    var sdir: u8[>..] = [];
    sdir.append(root);
    sdir.append("/seeds");
    make_dir(sdir);
    for f in 0..3 {
        var sp: u8[>..] = [];
        sp.append(sdir);
        sp.append("/s");
        format_int(sp, f, 10, 0, ' ');
        var data: u8[>..] = [];
        for i in 0..40 {
            data.push(((f * 13 + i * 7 + 1) % 256) as u8);
        }
        assert(write_file(sp, data));
    }
    var cfg = fuzz::config();
    cfg.runs = 20000;
    cfg.seed_dir.append(sdir);
    var croot: u8[>..] = [];
    croot.append(root);
    croot.append("/crash");
    cfg.crash_root.append(croot);
    for s in 1..11 {
        cfg.seed = s as u64;
        var rep = fuzz::Report { };
        assert(fuzz::run("typed", cfg, rep, targets::typed_target) == 1);
        let site = fuzz::finding_site(rep, 0);
        assert(find(site, "test/targets.goose:") >= 0);
        if s == 1 {
            // the crasher replays at the same site
            var rr = fuzz::Report { };
            assert(fuzz::replay("typed", croot, rr, targets::typed_target) == 1);
            assert(fuzz::finding_site(rr, 0) == site);
            // the shrunk input aborts at the same site
            var small: u8[>..] = [];
            assert(fuzz::shrink(fuzz::finding_input(rep, 0), small, targets::typed_target));
            assert(small.len < fuzz::finding_input(rep, 0).len);
            var why: u8[>..] = [];
            var got: u8[>..] = [];
            assert(fuzz::aborts_at(small, site, why, got, targets::typed_target));
        }
    }
    var d: u8[>..] = [];
    d.append(croot);
    d.append("/typed");
    clean_dir(d);
    clean_dir(sdir);
    delete_dir(root);
}

// The parallel workers: the seeds, the limit, the merge, the failures.
fn test_parallel() {
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-par");
    make_dir(root);
    // no two batches share a seed; the same seed repeats the run
    let s0 = fuzz::derive_seed(7, 0, 0);
    assert(s0 == fuzz::derive_seed(7, 0, 0));
    assert(s0 != fuzz::derive_seed(7, 1, 0));
    assert(s0 != fuzz::derive_seed(7, 0, 1));
    assert(s0 != fuzz::derive_seed(8, 0, 0));
    // a count above 15 is refused before any child starts
    let prog = args()[0];
    var cfg = fuzz::config();
    cfg.child.append(prog);
    cfg.seed = 1;
    cfg.runs = 100;
    cfg.workers = 16;
    var rep = fuzz::Report { };
    assert(fuzz::run_isolated("ok-child", cfg, rep) == -1);
    assert(rep.runs == 0);
    cfg.workers = 100;
    var rep2 = fuzz::Report { };
    assert(fuzz::run_isolated("ok-child", cfg, rep2) == -1);
    assert(rep2.runs == 0);
    // four workers that hit one site give one finding with summed hits
    var sdir: u8[>..] = [];
    sdir.append(root);
    sdir.append("/seeds");
    make_dir(sdir);
    var sp: u8[>..] = [];
    sp.append(sdir);
    sp.append("/m");
    var mark: u8[>..] = [];
    mark.push(61);
    assert(write_file(sp, mark));
    var cfg4 = fuzz::config();
    cfg4.child.append(prog);
    cfg4.seed = 1;
    cfg4.runs = 100;
    cfg4.workers = 4;
    cfg4.seed_dir.append(sdir);
    var croot: u8[>..] = [];
    croot.append(root);
    croot.append("/crash");
    cfg4.crash_root.append(croot);
    var rep4 = fuzz::Report { };
    assert(fuzz::run_isolated("exit-child", cfg4, rep4) == 1);
    assert(rep4.runs == 100);
    assert(fuzz::finding_count(rep4) == 1);
    assert(fuzz::finding_site(rep4, 0) == "child:exit 3");
    assert(fuzz::finding_hits(rep4, 0) == 4);
    // a missing child program with four workers frees them and fails
    var bad = fuzz::config();
    bad.child.append("no-such-child-program-xyz");
    bad.seed = 1;
    bad.runs = 10;
    bad.workers = 4;
    var rep5 = fuzz::Report { };
    assert(fuzz::run_isolated("ok-child", bad, rep5) == -1);
    var d: u8[>..] = [];
    d.append(croot);
    d.append("/exit-child");
    clean_dir(d);
    clean_dir(sdir);
    delete_dir(root);
}

// Four workers finish a slow run in two thirds of the time of one
// worker. The check needs four cores, so a smaller machine skips it.
fn test_speedup() {
    if fuzz::cores() < 4 {
        print("speedup skipped: fewer than four cores");
        return;
    }
    let prog = args()[0];
    var cfg1 = fuzz::config();
    cfg1.child.append(prog);
    cfg1.seed = 1;
    cfg1.runs = 1000;
    cfg1.workers = 1;
    var rep1 = fuzz::Report { };
    let t1 = clock_ns();
    assert(fuzz::run_isolated("slow-child", cfg1, rep1) == 0);
    let ms1 = (clock_ns() - t1) / 1000000;
    var cfg4 = fuzz::config();
    cfg4.child.append(prog);
    cfg4.seed = 1;
    cfg4.runs = 1000;
    cfg4.workers = 4;
    var rep4 = fuzz::Report { };
    let t4 = clock_ns();
    assert(fuzz::run_isolated("slow-child", cfg4, rep4) == 0);
    let ms4 = (clock_ns() - t4) / 1000000;
    assert(rep1.runs == 1000 && rep4.runs == 1000);
    print("speedup: one worker ", ms1, " ms, four workers ", ms4, " ms");
    assert(ms4 * 3 <= ms1 * 2);
}
