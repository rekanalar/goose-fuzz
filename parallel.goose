// The parallel parent of the child mode.
//
// The parent starts one child for each worker and waits within one
// deadline per round. The handle table of the process package holds 16
// slots and has no lock, so the parent stays single-threaded.
namespace fuzz;

import std;
import os;

// The hard limit of workers, one below the 16 slots of the process
// package.
const WORKER_MAX = 15;

// The default cap of the auto worker count.
const WORKER_CAP = 8;

// One integer that a probe program printed, from its last decimal
// digits. Returns 0 when the probe fails.
fn probe_int(cmd: const u8[:], a1: const u8[:], a2: const u8[:]) -> i64 {
    var args: const u8[:][>..] = [];
    if a1.len > 0 {
        args.push(a1);
    }
    if a2.len > 0 {
        args.push(a2);
    }
    var opts = process::options();
    opts.timeout_ms = 5000;
    let r = process::run(cmd, args, "", opts);
    if r.status != process::ENDED || r.code != 0 {
        return 0;
    }
    // The output ends in a newline. Walk back over the digits.
    var end = r.output.len;
    while end > 0 && (r.output[end - 1] < 48 || r.output[end - 1] > 57) {
        end -= 1;
    }
    var start = end;
    while start > 0 && r.output[start - 1] >= 48 && r.output[start - 1] <= 57 {
        start -= 1;
    }
    if start >= end {
        return 0;
    }
    let v, ok = parse_int(r.output[start..end]);
    if !ok {
        return 0;
    }
    return v;
}

// One worker for each core. The sources, in order: the environment
// variable NUMBER_OF_PROCESSORS, the program nproc, the program sysctl.
// The fallback is 1.
fn cores() -> i64 {
    var buf: u8[>..] = [];
    if env("NUMBER_OF_PROCESSORS", buf) {
        let t = trim(buf);
        let v, ok = parse_int(t);
        if ok && v > 0 {
            return v;
        }
    }
    let n = probe_int("nproc", "", "");
    if n > 0 {
        return n;
    }
    let m = probe_int("sysctl", "-n", "hw.ncpu");
    if m > 0 {
        return m;
    }
    return 1;
}

// The seed of one batch of one worker. It derives from the seed of the
// run, so the same seed and worker count repeat the run, and no two
// batches share a seed.
fn derive_seed(seed: u64, batch_no: i64, worker: i64) -> u64 {
    var buf: u8[>..] = [];
    push_be64(buf, seed);
    push_be64(buf, batch_no as u64);
    push_be64(buf, worker as u64);
    return fnv1a64(buf);
}

// Push the bytes of v, big-endian.
fn push_be64(buf: u8[>..]&, v: u64) {
    for i in 0..8 {
        buf.push(((v >> ((7 - i) * 8)) & 255) as u8);
    }
}

// The saved path of the worker w, under the run directory.
fn save_path_of(rundir: const u8[:], w: i64, out: u8[>..]&) {
    out.clear();
    out.append(rundir);
    out.append("save-");
    format_int(out, w, 10, 0, ' ');
}

// A private directory of this run under the scratch directory. The name
// holds the seed and the clock, so two runs never share a directory.
fn run_dir(scratch: const u8[:], seed: u64, out: u8[>..]&) {
    out.clear();
    out.append(scratch);
    out.append("/fuzz-child-");
    var buf: u8[>..] = [];
    let t = clock_ns();
    for i in 0..8 {
        buf.push(((seed >> ((7 - i) * 8)) & 255) as u8);
    }
    for i in 0..8 {
        buf.push((((t as u64) >> ((7 - i) * 8)) & 255) as u8);
    }
    hex16(out, fnv1a64(buf));
    out.append("/");
}

// One escape case of a worker. Reads the saved input, builds the site
// and the message, and records the finding.
fn record_escape(rep: Report&, status: i32, code: i32, save_path: const u8[:],
                 cfg: const Config&, name: const u8[:]) {
    var saved: u8[>..] = [];
    read_file(save_path, saved);
    var site: u8[>..] = [];
    var msg: u8[>..] = [];
    if status == process::STOPPED {
        site.append("child:stopped");
        msg.append("the child was stopped on the time limit");
    } else {
        site.append("child:exit ");
        format_int(site, code, 10, 0, ' ');
        msg.append("the child ended with code ");
        format_int(msg, code, 10, 0, ' ');
    }
    let at = record(rep, site, msg, saved);
    if at >= 0 && rep.findings[at].count == 1 {
        if save_crasher(cfg.crash_root, name, saved) {
            rep.findings[at].saved = true;
        } else {
            rep.save_failed += 1;
        }
    }
}

// Run the child in rounds of parallel workers. Each round spawns one
// child per worker, each with its own seed and saved path, and waits
// within one deadline. Returns the finding count, or -1 on a hard
// error. name keys the crasher directory.
fn run_rounds(name: const u8[:], cfg: const Config&, rep: Report&, seed: u64, workers: i64) -> i64 {
    var scratch: u8[>..] = [];
    env("TMPDIR", scratch);
    // The private directory of this run. Every file of the run lives in
    // it, so two runs never share a file.
    var rundir: u8[>..] = [];
    run_dir(scratch, seed, rundir);
    var plain: u8[>..] = [];
    plain.append(rundir[..rundir.len - 1]);
    make_dir(plain);
    // The dictionary file for the children, when the caller set tokens.
    var dict_path: u8[>..] = [];
    if cfg.dict.len > 0 {
        dict_path.append(rundir);
        dict_path.append("dict");
        write_file(dict_path, cfg.dict);
    }
    let t0 = clock_ns();
    // The children live as slot ids. The type Child of the process
    // package cannot be named here, so the low-level calls take the id.
    var kid_ids: i32[..16] = [];
    var takes: i64[..16] = [];
    var done: i64 = 0;
    var batch_no: i64 = 0;
    var spath: u8[>..] = [];
    var hard = false;
    while done < cfg.runs {
        if cfg.time_ms > 0 && (clock_ns() - t0) / 1000000 >= cfg.time_ms {
            break;
        }
        let left = cfg.runs - done;
        let per = min(CHILD_BATCH, (left + workers - 1) / workers);
        let deadline = clock_ns() + CHILD_LIMIT_MS * 1000000;
        var spawned: i64 = 0;
        var remaining = left;
        var w: i64 = 0;
        kid_ids.clear();
        takes.clear();
        // The text buffers live to the end of the round, so the slices
        // in cargs stay valid until spawn takes them.
        var tlen: u8[>..] = [];
        var tseed: u8[>..] = [];
        var trun: u8[>..] = [];
        var trate: u8[>..] = [];
        while w < workers && remaining > 0 {
            let take = min(per, remaining);
            save_path_of(rundir, w, spath);
            var cargs: const u8[:][>..] = [];
            cargs.push(CHILD_MARKER);
            cargs.push(cfg.seed_dir);
            tlen.clear();
            format_int(tlen, cfg.max_len, 10, 0, ' ');
            cargs.push(tlen);
            // The top bit goes away, because the debug build checks the
            // as conversion and the child takes the seed as an i64.
            let dseed = derive_seed(seed, batch_no, w) & 9223372036854775807;
            tseed.clear();
            format_int(tseed, dseed as i64, 10, 0, ' ');
            cargs.push(tseed);
            trun.clear();
            format_int(trun, take, 10, 0, ' ');
            cargs.push(trun);
            cargs.push(spath);
            cargs.push(cfg.crash_root);
            cargs.push(name);
            if dict_path.len > 0 {
                cargs.push(dict_path);
                trate.clear();
                format_int(trate, cfg.token_rate, 10, 0, ' ');
                cargs.push(trate);
            }
            var opts = process::options();
            let c = process::spawn(cfg.child, cargs, opts);
            if c.status != process::RUNNING {
                // A child that does not start is a hard error. The
                // children that run are stopped.
                for k in 0..spawned {
                    process::proc_free(kid_ids[k]);
                }
                spawned = 0;
                hard = true;
                break;
            }
            kid_ids.push(c.id);
            takes.push(take);
            spawned += 1;
            remaining -= take;
            w += 1;
        }
        if hard {
            break;
        }
        for k in 0..spawned {
            save_path_of(rundir, k, spath);
            var leftms = (deadline - clock_ns()) / 1000000;
            if leftms < 1 {
                leftms = 1;
            }
            var code: i32 = 0;
            let st = process::proc_wait(kid_ids[k], code, leftms as i32);
            if st == process::ENDED && code == CHILD_ERROR {
                hard = true;
            } else if !(st == process::ENDED && code == 0) {
                record_escape(rep, st, code, spath, cfg, name);
            }
            process::proc_free(kid_ids[k]);
            done += takes[k];
            rep.runs += takes[k];
        }
        if hard {
            break;
        }
        batch_no += 1;
    }
    if dict_path.len > 0 {
        delete_file(dict_path);
    }
    for w in 0..workers {
        save_path_of(rundir, w, spath);
        delete_file(spath);
    }
    delete_dir(plain);
    if hard {
        return -1;
    }
    return finding_count(rep);
}
