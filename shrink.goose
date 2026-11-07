// Shorten an input that aborts, and keep the abort site.
namespace fuzz;

import std;

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
fn shrink<W>(input: const u8[:], out: u8[>..]&) -> bool {
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
    // Remove chunks of half, quarter, ... one byte. Keep a removal when
    // the abort site stays the same.
    var n = cur.len / 2;
    if n < 1 {
        n = 1;
    }
    while n >= 1 {
        var off: i64 = 0;
        while off < cur.len {
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
    out.clear();
    out.append(cur);
    return true;
}
