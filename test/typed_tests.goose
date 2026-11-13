// The tests of the typed target: it finds, replays and shrinks.
namespace typed_tests;

import std;
import os;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "..";
import targets;
import work_dirs;
import seed_pool;

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
    work_dirs::clean_dir(d);
    work_dirs::clean_dir(sdir);
    delete_dir(root);
}
