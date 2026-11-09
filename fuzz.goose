// fuzz: seeded fuzzing for Goose programs.
//
// Each input runs in a contained worker. An abort in the worker is a
// finding, and the run goes on. The classes of the hit counts decide
// which input joins the pool, and the energy of a seed decides when the
// pool moves on to the next seed.
namespace fuzz;

import std;
import fnv;
import site;
import report;
import config;
import cov;
import exec;
import mutate;
import dict;
import reader;
import score;
import parallel;
import corpus;
import shrink;
import child;
import os;
import process from "rekanalar/goose-process@v1.0.0";

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

// The run with the mutator of the caller. The target and the mutator
// travel as the trailing values of the call, and each binds one
// generic of the loop.
fn run_mut<W, M>(name: const u8[:], cfg: const Config&, rep: Report&) -> i64 {
    var pool: u8[>..] = [];
    var seeds: Seed[>..] = [];
    if cfg.seed_dir.len > 0 {
        if load_seeds(cfg.seed_dir, cfg.max_len, cfg.seed_energy, pool, seeds) < 0 {
            return -1;
        }
    }
    // The corpus of the last run is a seed of this run. A corpus
    // directory that does not exist holds no files.
    var corpus_files = load_corpus(cfg.corpus_root, name, cfg.max_len, cfg.seed_energy,
                                   pool, seeds);
    var seed = cfg.seed;
    if seed == 0 {
        seed = random_seed();
    }
    rep.seed = seed;
    var r = rng { seed };
    // The dictionary text is parsed once. A bad line is skipped; the
    // tokens before it stay.
    var dpool: u8[>..] = [];
    var dends: i64[>..] = [];
    if cfg.dict.len > 0 {
        var derr: u8[>..] = [];
        dict_parse(cfg.dict, dpool, dends, derr);
    }
    // Each seed runs once as it is. With no seed, the empty input runs
    // once.
    let first = max(seeds.len, 1);
    var limit = cfg.runs;
    if limit == 0 {
        limit = first;
    }
    // The coverage of this run starts empty.
    cov_reset();
    let t0 = clock_ns();
    var cur: u8[>..] = [];
    var bbuf: u8[>..] = [];
    var mbuf: u8[>..] = [];
    var why: u8[>..] = [];
    var site: u8[>..] = [];
    var src: i64 = -1;
    // The input with the best score. The arena of the report holds it
    // at the end of the run.
    var best: u8[>..] = [];
    for i in 0..limit {
        if cfg.time_ms > 0 && (clock_ns() - t0) / 1000000 >= cfg.time_ms {
            break;
        }
        var kind: i64 = -1;
        cur.clear();
        if i < first && i < seeds.len {
            // Each seed runs once as it is.
            bbuf.clear();
            bbuf.append(seed_at(pool, seeds, i, cfg.max_len));
            src = i;
            cur.append(bbuf);
        } else if i >= first {
            src = -1;
            var base_at: i64 = -1;
            // The score modes mutate the best input half of the time.
            if cfg.score_mode > 0 && best.len > 0 && r.rand_int(2) == 0 {
                bbuf.clear();
                bbuf.append(best);
            } else {
                base_at = pick_index(r, seeds, cfg.pool_order);
                bbuf.clear();
                if base_at >= 0 {
                    bbuf.append(seed_at(pool, seeds, base_at, cfg.max_len));
                }
            }
            // The mutator of the caller runs at its rate. A false
            // result falls back to a kind of the table.
            var made = false;
            if cfg.mutator_rate > 0 && r.rand_int(100) < cfg.mutator_rate {
                mbuf.clear();
                if M(bbuf, mbuf) {
                    made = true;
                    if mbuf.len > cfg.max_len {
                        mbuf.resize(cfg.max_len);
                    }
                }
            }
            if made {
                cur.append(mbuf);
            } else {
                src = base_at;
                kind = mutate_base(r, pool, bbuf, seeds, cfg.max_len, cur);
                // The dictionary steers the mutation. A token replaces
                // the kind of the byte mutation.
                let tk = apply_token(r, dpool, dends, cfg.token_rate, cfg.max_len, cur);
                if tk >= 0 {
                    kind = tk;
                }
            }
        }
        let t1 = clock_ns();
        let at = try_input(cur, rep, why, site, W);
        let t2 = clock_ns();
        // The count of the classes that this input rose. It is zero
        // without the coverage.
        let fresh = cov_end();
        // The score of the input: the value of the target, or the
        // time. The poll drains the queue of the scores.
        // The queue is drained in every mode, so a target that scores
        // while the mode is off cannot make it grow.
        var sc = poll_score();
        if cfg.score_mode == 2 {
            sc = (t2 - t1) as f64 / 1000000.0;
        }
        if cfg.score_mode > 0 && sc > rep.best_score {
            rep.best_score = sc;
            best.clear();
            best.append(cur);
        }
        if kind >= 0 && kind < 20 {
            rep.kind_count[kind] += 1;
        }
        if fresh > 0 {
            rep.interesting += 1;
            // The input joins the seeds of the later mutations, and
            // the classes that it reached first are its hits.
            pool.append(cur);
            var s = Seed { };
            s.off = pool.len - cur.len;
            s.len = cur.len;
            s.energy = cfg.seed_energy;
            s.hits = fresh as i64;
            seeds.push(s);
            // The corpus keeps the input for the next run.
            if corpus_files < CORPUS_MAX {
                let made = save_corpus(cfg.corpus_root, name, cur);
                if made > 0 {
                    corpus_files += 1;
                } else if made < 0 {
                    rep.corpus_dropped += 1;
                }
            } else {
                rep.corpus_dropped += 1;
            }
        } else if cfg.seed_energy > 0 && src >= 0 && src < seeds.len {
            // The mutation of this seed found nothing new. It spends
            // one of the mutations of the seed. A seed at zero stays in
            // the pool, and the next choice prefers the seeds that have
            // energy. When no seed has energy, the cycle ends and every
            // seed gets its energy again.
            seeds[src].energy -= 1;
            if seeds[src].energy == 0 {
                rep.seeds_retired += 1;
                var spent = true;
                for k in 0..seeds.len {
                    if seeds[k].energy > 0 {
                        spent = false;
                        break;
                    }
                }
                if spent {
                    for k in 0..seeds.len {
                        seeds[k].energy = cfg.seed_energy;
                    }
                }
            }
        }
        if at >= 0 && rep.findings[at].count == 1 {
            if save_crasher(cfg.crash_root, name, cur) {
                rep.findings[at].saved = true;
            } else {
                rep.save_failed += 1;
            }
        }
    }
    rep.edges = cov_total() as i64;
    rep.edges_lost = cov_lost() as i64;
    // The classes of the run. The class 0 holds the edges that no
    // input of the run reached, and it is the distinct edges minus
    // the rest.
    var csum: i64 = 0;
    for c in 1..9 {
        let v = cov_class_edges(c) as i64;
        rep.class_edges[c] = v;
        csum += v;
    }
    rep.class_edges[0] = rep.edges - csum;
    // The input with the best score joins the arena once, at the end.
    if best.len > 0 {
        rep.best_off = rep.arena.len;
        rep.best_len = best.len;
        rep.arena.append(best);
    }
    return finding_count(rep);
}

// Fuzz the target W. The loop runs the kinds of the table, because the
// mutator of the package never writes.
fn run<W>(name: const u8[:], cfg: const Config&, rep: Report&) -> i64 {
    return run_mut(name, cfg, rep, W, no_mutator);
}

// Fuzz the target W with the mutator of the caller. The mutator takes
// the input and a buffer, and it returns true when it wrote an input.
// The buffer holds at most cfg.max_len bytes after the call.
fn run_with<W, M>(name: const u8[:], cfg: const Config&, rep: Report&) -> i64 {
    return run_mut(name, cfg, rep, W, M);
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
    // The coverage comes last, and only a program that was built with
    // the coverage flag has it.
    if cov_live() {
        out.append("edges: ");
        format_int(out, rep.edges, 10, 0, ' ');
        out.append("\ninteresting: ");
        format_int(out, rep.interesting, 10, 0, ' ');
        out.append("\n");
        if rep.edges_lost > 0 {
            out.append("edges lost: ");
            format_int(out, rep.edges_lost, 10, 0, ' ');
            out.append("\n");
        }
    }
    if rep.slow > 0 {
        out.append("slow: ");
        format_int(out, rep.slow, 10, 0, ' ');
        out.append("\n");
    }
    if rep.seeds_retired > 0 {
        out.append("seeds retired: ");
        format_int(out, rep.seeds_retired, 10, 0, ' ');
        out.append("\n");
    }
    if rep.best_score > 0.0 {
        out.append("best score: ");
        format_flt(out, rep.best_score, 3);
        out.append("\n");
    }
}

// Run every crasher file of name once. Records each abort in rep. Returns
// the number of files that aborted. A missing directory returns 0.
fn replay<W>(name: const u8[:], crash_root: const u8[:], rep: Report&) -> i64 {
    var dir: u8[>..] = [];
    crash_dir(crash_root, name, dir);
    var pool: u8[>..] = [];
    var seeds: Seed[>..] = [];
    if load_seeds(dir, 1 << 40, 1, pool, seeds) <= 0 {
        return 0;
    }
    var failed: i64 = 0;
    var why: u8[>..] = [];
    var site: u8[>..] = [];
    for i in 0..seeds.len {
        if try_input(seed_at(pool, seeds, i, 1 << 40), rep, why, site, W) != -2 {
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
// child ended with a code, child:stopped when the limit passed. The
// probe runs the suspect input again in one child within the time of
// cfg.probe_ms, and a clean probe makes the finding child:slow. The
// workers of cfg.workers run at the same time, with a seed for each
// batch and worker. Returns the finding count, or -1 when the child
// name is empty, unknown, the worker count is above 15, or the child
// reports an error.
fn run_isolated(name: const u8[:], cfg: const Config&, rep: Report&) -> i64 {
    if cfg.child.len == 0 {
        return -1;
    }
    var workers = cfg.workers;
    if workers <= 0 {
        workers = cores();
        if workers > WORKER_CAP {
            workers = WORKER_CAP;
        }
    }
    if workers > WORKER_MAX {
        return -1;
    }
    var seed = cfg.seed;
    if seed == 0 {
        seed = random_seed();
    }
    rep.seed = seed;
    return run_rounds(name, cfg, rep, seed, workers);
}
