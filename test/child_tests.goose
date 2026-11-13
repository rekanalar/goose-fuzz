// The tests of the child mode: the probe of the parent and the batch of the child.
namespace child_tests;

import std;
import os;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "..";
import targets;
import work_dirs;
import seed_pool;

// The probe of the parent. A slow input ends the probe, and a hang
// stops the probe again.
fn test_probe() {
    let prog = args()[0];
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-probe-root");
    work_dirs::clean_dir(root);
    var cfg = fuzz::config();
    cfg.crash_root.append(root);
    cfg.child.append(prog);
    cfg.seed = 8;
    cfg.runs = 100;
    var rep = fuzz::Report { };
    assert(fuzz::run_isolated("slow12-child", cfg, rep) == 1);
    assert(fuzz::finding_site(rep, 0) == "child:slow");
    assert(rep.slow >= 1 && rep.slow == fuzz::finding_hits(rep, 0));
    work_dirs::clean_dir(root);
    delete_dir(root);
}

// The child mode: the exit case, the hang case, the clean batch, the
// rate, and the hard errors.
fn test_child() {
    let prog = args()[0];
    var root: u8[>..] = [];
    env("TMPDIR", root);
    root.append("/fz-child-root");
    work_dirs::clean_dir(root);

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

    work_dirs::clean_dir(root);
    delete_dir(root);
}
