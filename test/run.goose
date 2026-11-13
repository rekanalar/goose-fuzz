// Tests for the fuzz package.
//
// Build and run: goose build --debug test/run.goose -o <file>, then run <file>.
// The tests start worker threads, so "goose run" cannot run them.

import std;
import os;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "..";
import targets;
import work_dirs;
import seed_pool;
import child_tests;
import dict_tests;
import reader_tests;
import typed_tests;
import parallel_tests;

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


fn test_mutate() {
    var pool: u8[>..] = [];
    var seeds: fuzz::Seed[>..] = [];
    seed_pool::seeds16(pool, seeds);
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
    seed_pool::seeds16(pool, seeds);
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

fn test_corpus() {
    var dir: u8[>..] = [];
    work_dirs::scratch("fz-seeds", dir);
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
        work_dirs::clean_dir(d);
    }
    delete_dir(root);
    // report text
    var txt: u8[>..] = [];
    fuzz::format_report(txt, r4);
    assert(find(txt, "test/targets.goose:") >= 0);
}


fn test_crashers() {
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-crash-root");
    var sub: u8[>..] = [];
    sub.append(root);
    sub.append("/assert");
    work_dirs::clean_dir(sub);
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
    work_dirs::clean_dir(sub);
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
    work_dirs::clean_dir(d);
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
        work_dirs::clean_dir(d);
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
    work_dirs::scratch("fz-limit-seeds", dir);
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
    work_dirs::clean_dir(dir);
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
    work_dirs::clean_dir(sub);
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
    dict_tests::test_dict();
    dict_tests::test_dict_run();
    dict_tests::test_dict_child();
    reader_tests::test_reader();
    test_coverage_fields();
    typed_tests::test_typed();
    parallel_tests::test_parallel();
    parallel_tests::test_speedup();
    test_pool();
    test_score();
    test_run_with();
    child_tests::test_probe();
    child_tests::test_child();
    print("ok hash, site, report, exec, mutate, child, dict, reader, typed, parallel");
    return 0;
}

// The pool: a seed that finds nothing loses its energy and leaves it.
// The order that takes the best seed first runs clean too.
fn test_pool() {
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-pool-root");
    work_dirs::clean_dir(root);
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

    work_dirs::clean_dir(root);
    delete_dir(root);
}

// The score of the target steers the run, and the time of the run does
// too.
fn test_score() {
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-score-root");
    work_dirs::clean_dir(root);
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
    work_dirs::clean_dir(root);
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
    work_dirs::clean_dir(root);
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

    work_dirs::clean_dir(root);
    delete_dir(root);
}
