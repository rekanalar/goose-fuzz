// The tests of the dictionary: the parser, the loaders and the reproducibility.
namespace dict_tests;

import std;
import os;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "..";
import targets;
import work_dirs;
import seed_pool;

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
    seed_pool::seeds16(pool, seeds);
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
    work_dirs::clean_dir(d);
    work_dirs::clean_dir(sdir);
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
    work_dirs::clean_dir(cdir);
    delete_dir(root);
}
