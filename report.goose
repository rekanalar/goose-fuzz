// The report of one fuzz run.
//
// A finding holds offsets into one arena. A struct may hold one growable
// field, and it must come last, so all bytes live in the arena.
namespace fuzz;

import std;

struct Finding {
    site_off: i64 = 0,
    site_len: i64 = 0,
    msg_off: i64 = 0,
    msg_len: i64 = 0,
    input_off: i64 = 0,
    input_len: i64 = 0,
    // The number of runs that reached the site, at least 1.
    count: i64 = 0,
    saved: bool = false,
}

struct Report {
    seed: u64 = 0,
    runs: i64 = 0,
    // Aborts at a 257th site and later.
    dropped: i64 = 0,
    save_failed: i64 = 0,
    // The distinct edges that the run reached. It is zero without the
    // coverage.
    edges: i64 = 0,
    // The addresses that found the table of the edges full, and so
    // went unseen. It is zero without the coverage.
    edges_lost: i64 = 0,
    // The inputs that made the class of an edge rise above the class
    // of any earlier input. It is zero without the coverage.
    interesting: i64 = 0,
    // The interesting inputs that the cap of the corpus turned away.
    corpus_dropped: i64 = 0,
    // The edges whose highest class is the index. The index 0 holds
    // the edges that no input of the run reached, and it is the
    // distinct edges minus the rest. The classes hold 1 to 8.
    class_edges: i64[9] = [0, 0, 0, 0, 0, 0, 0, 0, 0],
    // The mutations of each kind. The kinds 0 to 5 keep their meaning,
    // and the kinds 6 to 19 are the new kinds. A mutation of the
    // caller holds no kind.
    kind_count: i64[20] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    // The inputs that ended the probe of the parent. Such an input is
    // slow, and not a hang.
    slow: i64 = 0,
    // The seeds that spent their energy and left the pool.
    seeds_retired: i64 = 0,
    // The highest score of the run. The score is the value of the
    // target in the score mode 1, and the time of the run in the
    // score mode 2. Zero without a score mode, and in the child mode.
    best_score: f64 = 0.0,
    best_off: i64 = 0,
    best_len: i64 = 0,
    findings: Finding[..256] = [],
    // The arena must stay the last field.
    arena: u8[>..] = [],
}

fn finding_count(rep: const Report&) -> i64 {
    return rep.findings.len;
}

fn finding_site(rep: const Report&, i: i64) -> const u8[:] {
    let f = rep.findings[i];
    return rep.arena[f.site_off..f.site_off + f.site_len];
}

fn finding_message(rep: const Report&, i: i64) -> const u8[:] {
    let f = rep.findings[i];
    return rep.arena[f.msg_off..f.msg_off + f.msg_len];
}

fn finding_input(rep: const Report&, i: i64) -> const u8[:] {
    let f = rep.findings[i];
    return rep.arena[f.input_off..f.input_off + f.input_len];
}

fn finding_hits(rep: const Report&, i: i64) -> i64 {
    return rep.findings[i].count;
}

// The input that holds the best score. Empty when the run holds no
// score.
fn best_input(rep: const Report&) -> const u8[:] {
    return rep.arena[rep.best_off..rep.best_off + rep.best_len];
}

// The index of the finding with this site, or -1.
fn find_site(rep: const Report&, site: const u8[:]) -> i64 {
    for i in 0..rep.findings.len {
        if finding_site(rep, i) == site {
            return i;
        }
    }
    return -1;
}

// Count one abort. A new site adds a finding. Returns the finding index,
// or -1 when the report holds 256 findings already.
fn record(rep: Report&, site: const u8[:], msg: const u8[:], input: const u8[:]) -> i64 {
    let at = find_site(rep, site);
    if at >= 0 {
        rep.findings[at].count += 1;
        return at;
    }
    if rep.findings.len >= 256 {
        rep.dropped += 1;
        return -1;
    }
    var f = Finding { };
    f.site_off = rep.arena.len;
    f.site_len = site.len;
    rep.arena.append(site);
    f.msg_off = rep.arena.len;
    f.msg_len = msg.len;
    rep.arena.append(msg);
    f.input_off = rep.arena.len;
    f.input_len = input.len;
    rep.arena.append(input);
    f.count = 1;
    rep.findings.push(f);
    return rep.findings.len - 1;
}
