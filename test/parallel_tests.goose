// The tests of the parallel workers: the seeds, the limit, the merge and the speedup.
namespace parallel_tests;

import std;
import os;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "..";
import targets;
import work_dirs;
import seed_pool;

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
    work_dirs::clean_dir(d);
    work_dirs::clean_dir(sdir);
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
