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
import os;

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
