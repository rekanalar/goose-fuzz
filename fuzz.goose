// fuzz: seeded fuzzing for Goose programs.
//
// Each input runs in a contained worker. An abort in the worker is a
// finding, and the run goes on.
namespace fuzz;

import std;
import fnv;
import site;
import report;
import config;
import exec;
import mutate;
import corpus;
import shrink;
import child;
import os;
import process from "rekanalar/goose-process@v0.1.1";

// Run W on one input and count the run in rep. An abort is recorded.
// Returns -2 when the input passed, else the finding index (-1 if dropped).
fn try_input<W>(input: const u8[:], rep: Report&, why: u8[>..]&, site: u8[>..]&) -> i64 {
    why.clear();
    rep.runs += 1;
    if run_one(input, why, W) {
        return -2;
    }
    site.clear();
    site_of(why, site);
    return record(rep, site, why, input);
}

// Run W on many inputs. Fills rep. Returns the number of findings, or -1
// when the seed directory cannot be read. name keys the crasher directory.
fn run<W>(name: const u8[:], cfg: const Config&, rep: Report&) -> i64 {
    var pool: u8[>..] = [];
    var ends: i64[>..] = [];
    if cfg.seed_dir.len > 0 {
        if load_seeds(cfg.seed_dir, cfg.max_len, pool, ends) < 0 {
            return -1;
        }
    }
    var seed = cfg.seed;
    if seed == 0 {
        seed = random_seed();
    }
    rep.seed = seed;
    var r = rng { seed };
    // Each seed runs once as it is. With no seed, the empty input runs once.
    let first = max(ends.len, 1);
    var limit = cfg.runs;
    if limit == 0 {
        limit = first;
    }
    let t0 = clock_ns();
    var cur: u8[>..] = [];
    var why: u8[>..] = [];
    var site: u8[>..] = [];
    for i in 0..limit {
        if cfg.time_ms > 0 && (clock_ns() - t0) / 1000000 >= cfg.time_ms {
            break;
        }
        cur.clear();
        if i < ends.len {
            cur.append(seed_at(pool, ends, i, cfg.max_len));
        } else if i >= first {
            mutate_next(r, pool, ends, cfg.max_len, cur);
        }
        let at = try_input(cur, rep, why, site, W);
        if at >= 0 && rep.findings[at].count == 1 {
            if save_crasher(cfg.crash_root, name, cur) {
                rep.findings[at].saved = true;
            } else {
                rep.save_failed += 1;
            }
        }
    }
    return finding_count(rep);
}

// Append a text report: the seed, the runs, then one block per finding.
fn format_report(out: u8[>..]&, rep: const Report&) {
    out.append("seed: ");
    format_uint(out, rep.seed, 10, 0, ' ');
    out.append("\nruns: ");
    format_int(out, rep.runs, 10, 0, ' ');
    out.append("\nfindings: ");
    format_int(out, finding_count(rep), 10, 0, ' ');
    out.append("\n");
    for i in 0..finding_count(rep) {
        out.append(finding_site(rep, i));
        out.append(" hits ");
        format_int(out, finding_hits(rep, i), 10, 0, ' ');
        out.append(": ");
        out.append(finding_message(rep, i));
        out.append("\n");
    }
}

// Run every crasher file of name once. Records each abort in rep. Returns
// the number of files that aborted. A missing directory returns 0.
fn replay<W>(name: const u8[:], crash_root: const u8[:], rep: Report&) -> i64 {
    var dir: u8[>..] = [];
    crash_dir(crash_root, name, dir);
    var pool: u8[>..] = [];
    var ends: i64[>..] = [];
    if load_seeds(dir, 1 << 40, pool, ends) <= 0 {
        return 0;
    }
    var failed: i64 = 0;
    var why: u8[>..] = [];
    var site: u8[>..] = [];
    for i in 0..ends.len {
        if try_input(seed_at(pool, ends, i, 1 << 40), rep, why, site, W) != -2 {
            failed += 1;
        }
    }
    return failed;
}

// The parent side of the child mode.
//
// The parent runs the child in batches. A child that dies or hangs turns
// its last saved input into a finding, and the run goes on. The root
// file of the program declares the process package.
const CHILD_BATCH = 500;
const CHILD_LIMIT_MS = 10000;

// Run the child over batches until cfg.runs or cfg.time_ms is met. An
// escape case is a finding with a synthetic site: child:exit N when the
// child ended with a code, child:stopped when the limit passed. Returns
// the finding count, or -1 when the child name is empty, unknown, or the
// child reports an error.
fn run_isolated(name: const u8[:], cfg: const Config&, rep: Report&) -> i64 {
    if cfg.child.len == 0 {
        return -1;
    }
    var seed = cfg.seed;
    if seed == 0 {
        seed = random_seed();
    }
    rep.seed = seed;
    let t0 = clock_ns();
    var scratch: u8[>..] = [];
    env("TMPDIR", scratch);
    scratch.append("/fuzz-child-save");
    var done: i64 = 0;
    var saved: u8[>..] = [];
    var site: u8[>..] = [];
    var msg: u8[>..] = [];
    while done < cfg.runs {
        if cfg.time_ms > 0 && (clock_ns() - t0) / 1000000 >= cfg.time_ms {
            break;
        }
        var batch = cfg.runs - done;
        if batch > CHILD_BATCH {
            batch = CHILD_BATCH;
        }
        var cargs: const u8[:][>..] = [];
        cargs.push(CHILD_MARKER);
        cargs.push(cfg.seed_dir);
        var tlen: u8[>..] = [];
        format_int(tlen, cfg.max_len, 10, 0, ' ');
        cargs.push(tlen);
        var tseed: u8[>..] = [];
        format_int(tseed, seed as i64, 10, 0, ' ');
        cargs.push(tseed);
        var trun: u8[>..] = [];
        format_int(trun, batch, 10, 0, ' ');
        cargs.push(trun);
        cargs.push(scratch);
        cargs.push(cfg.crash_root);
        cargs.push(name);
        var opts = process::options();
        opts.timeout_ms = CHILD_LIMIT_MS;
        let r = process::run(cfg.child, cargs, "", opts);
        if r.status == process::REFUSED || r.status == process::NOT_STARTED {
            return -1;
        }
        if r.status == process::ENDED && r.code == CHILD_ERROR {
            return -1;
        }
        // Every end below counts the batch as done, so the run reaches
        // its run count even when the same input crashes every batch.
        done += batch;
        rep.runs += batch;
        if r.status == process::ENDED && r.code == 0 {
            continue;
        }
        // An escape case. The input the child saved last is the input
        // that caused it.
        saved.clear();
        read_file(scratch, saved);
        site.clear();
        msg.clear();
        if r.status == process::STOPPED {
            site.append("child:stopped");
            msg.append("the child was stopped on the time limit");
        } else {
            site.append("child:exit ");
            format_int(site, r.code, 10, 0, ' ');
            msg.append("the child ended with code ");
            format_int(msg, r.code, 10, 0, ' ');
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
    delete_file(scratch);
    return finding_count(rep);
}
