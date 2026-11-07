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
