// Tests for the fuzz package.
//
// Build and run: goose build --debug test/run.goose -o <file>, then run <file>.
// The tests start worker threads, so "goose run" cannot run them.

import std;
import os;
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

fn seeds16(pool: u8[>..]&, ends: i64[>..]&) {
    for i in 0..16 {
        pool.push(i as u8);
    }
    ends.push(16);
}

fn test_mutate() {
    var pool: u8[>..] = [];
    var ends: i64[>..] = [];
    seeds16(pool, ends);
    var r = rng { 1 };
    var seen: i64[4] = [0, 0, 0, 0];
    var out: u8[>..] = [];
    for i in 0..10000 {
        out.clear();
        let k = fuzz::mutate_next(r, pool, ends, 16, out);
        assert(out.len <= 16);
        seen[k] += 1;
    }
    for k in 0..4 {
        assert(seen[k] > 0);
    }
    // the same seed gives the same inputs
    var a: u8[>..] = [];
    var b: u8[>..] = [];
    var ra = rng { 7 };
    var rb = rng { 7 };
    for i in 0..100 {
        out.clear();
        fuzz::mutate_next(ra, pool, ends, 16, out);
        a.append(out);
        out.clear();
        fuzz::mutate_next(rb, pool, ends, 16, out);
        b.append(out);
    }
    assert(a == b);
    // no seeds: starts from the empty input
    var none: i64[>..] = [];
    var nopool: u8[>..] = [];
    for i in 0..100 {
        out.clear();
        fuzz::mutate_next(ra, nopool, none, 4, out);
        assert(out.len <= 4);
    }
}

// The first 8 inputs of seed 1, recorded on v2026.3 and equal on v2026.4.
fn test_mutate_table() {
    var pool: u8[>..] = [];
    var ends: i64[>..] = [];
    seeds16(pool, ends);
    var r = rng { 1 };
    var out: u8[>..] = [];
    var all: u8[>..] = [];
    for n in 0..8 {
        out.clear();
        fuzz::mutate_next(r, pool, ends, 16, out);
        for b in out {
            format_uint(all, b, 16, 2, '0');
        }
        all.push('/');
    }
    assert(all == "000102030405060708090a0b03040506/000102030405a8060708090a0b0c0d0e/000102030405c0060708090a0b0c0d0e/000102030405060708090a030c0d0e0f/0001020304050607090a0b0c0d0e0f/000102030405060708090a0b0c1d0e0f/000102030405060708090a0b0c0d0e0c/000102030405060708092a0b0c0d0e0f/");
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
    assert(fuzz::load_seeds(dir, 4, pool, ends) == 2);
    assert(pool == "xy0123");
    assert(ends.len == 2 && ends[0] == 2 && ends[1] == 6);
    delete_file(pa);
    delete_file(pb);
    delete_dir(dir);
    var pool2: u8[>..] = [];
    var ends2: i64[>..] = [];
    assert(fuzz::load_seeds(dir, 4, pool2, ends2) == -1);
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
    // planted assert at targets.goose:14, ten fixed seeds, SC-001
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
    assert(r7.runs == 10000 && fuzz::finding_hits(r7, 0) == 10);
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
    // an unwritable root keeps the finding
    var bad = fuzz::config();
    bad.seed = 1;
    bad.runs = 10000;
    bad.crash_root.append("/proc/fz-no-such-root");
    var rb = fuzz::Report { };
    assert(fuzz::run("assert", bad, rb, targets::assert_target) == 1);
    assert(!rb.findings[0].saved && rb.save_failed == 1);
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

fn main() {
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
    print("ok hash, site, report, exec, mutate");
    return 0;
}
