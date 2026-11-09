// Shorten an input that aborts, and keep the abort site.
namespace fuzz;

import std;

// The budget of the steps of the shrink. A step is one candidate that
// the shrink runs.
const SHRINK_BUDGET = 20000;

// True when W aborts on input at the site.
fn aborts_at<W>(input: const u8[:], site: const u8[:], why: u8[>..]&, got: u8[>..]&) -> bool {
    why.clear();
    if run_one(input, why, W) {
        return false;
    }
    got.clear();
    site_of(why, got);
    return got == site;
}

// Fill out with a shorter input that aborts at the same site as input.
// Returns false, and leaves out alone, when input does not abort.
// stopped holds 1 when the budget ended the work, else 0.
fn shrink_full<W>(input: const u8[:], out: u8[>..]&, stopped: i64&) -> bool {
    stopped = 0;
    var why: u8[>..] = [];
    var site: u8[>..] = [];
    if run_one(input, why, W) {
        return false;
    }
    site_of(why, site);
    var cur: u8[>..] = [];
    cur.append(input);
    var cand: u8[>..] = [];
    var got: u8[>..] = [];
    var steps: i64 = 0;
    var ended = false;
    // The block pass. Remove chunks of half, quarter, ... one byte.
    // Keep a removal when the abort site stays the same.
    var n = cur.len / 2;
    if n < 1 {
        n = 1;
    }
    while n >= 1 && !ended {
        var off: i64 = 0;
        while off < cur.len {
            if steps >= SHRINK_BUDGET {
                ended = true;
                break;
            }
            steps += 1;
            let take = min(n, cur.len - off);
            cand.clear();
            cand.append(cur[0..off]);
            cand.append(cur[off + take..cur.len]);
            if aborts_at(cand, site, why, got, W) {
                cur.clear();
                cur.append(cand);
            } else {
                off += take;
            }
        }
        n = n / 2;
    }
    // The value pass. Write the byte zero over every byte of one value,
    // one value at a time.
    var value: i64 = 0;
    while value < 256 && !ended {
        var hits = false;
        for i in 0..cur.len {
            if cur[i] == value as u8 {
                hits = true;
                break;
            }
        }
        if hits && value != 0 {
            if steps >= SHRINK_BUDGET {
                ended = true;
                break;
            }
            steps += 1;
            cand.clear();
            for i in 0..cur.len {
                if cur[i] == value as u8 {
                    cand.push(0);
                } else {
                    cand.push(cur[i]);
                }
            }
            if aborts_at(cand, site, why, got, W) {
                cur.clear();
                cur.append(cand);
            }
        }
        value += 1;
    }
    // The byte pass. Take one byte of the input at a time, and try to
    // remove it.
    var off: i64 = 0;
    while off < cur.len && !ended {
        if steps >= SHRINK_BUDGET {
            ended = true;
            break;
        }
        steps += 1;
        cand.clear();
        cand.append(cur[0..off]);
        cand.append(cur[off + 1..cur.len]);
        if aborts_at(cand, site, why, got, W) {
            cur.clear();
            cur.append(cand);
        } else {
            off += 1;
        }
    }
    if ended {
        stopped = 1;
    }
    out.clear();
    out.append(cur);
    return true;
}

// Fill out with a shorter input that aborts at the same site as input.
// The budget of the steps ends the work, and the caller does not learn
// that it did. Use shrink_full to learn it.
fn shrink<W>(input: const u8[:], out: u8[>..]&) -> bool {
    var s: i64 = 0;
    return shrink_full(input, out, s, W);
}
