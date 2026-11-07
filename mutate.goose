// Mutate a seed into a new input.
//
// Seeds sit in one pool. ends[i] is the end offset of seed i.
namespace fuzz;

import std;

// The bytes of seed i, cut to max_len.
fn seed_at(pool: const u8[:], ends: const i64[:], i: i64, max_len: i64) -> const u8[:] {
    var start: i64 = 0;
    if i > 0 {
        start = ends[i - 1];
    }
    var stop = ends[i];
    if stop - start > max_len {
        stop = start + max_len;
    }
    return pool[start..stop];
}

// The bytes of a random seed, cut to max_len. Empty when there is no seed.
fn pick_seed(r: rng&, pool: const u8[:], ends: const i64[:], max_len: i64) -> const u8[:] {
    if ends.len == 0 {
        return pool[0..0];
    }
    return seed_at(pool, ends, r.rand_int(ends.len), max_len);
}

// Append one mutated input to out. Returns the kind: 0 flip, 1 insert,
// 2 delete, 3 splice. All choices come from r, so a seed repeats a run.
fn mutate_next(r: rng&, pool: const u8[:], ends: const i64[:], max_len: i64, out: u8[>..]&) -> i64 {
    let base = pick_seed(r, pool, ends, max_len);
    let kind = r.rand_int(4);
    if kind == 0 {
        out.append(base);
        if base.len > 0 {
            let at = out.len - base.len + r.rand_int(base.len);
            out[at] = out[at] ^ (1 << (r.rand_int(8) as u8));
        }
    } else if kind == 1 {
        let pos = r.rand_int(base.len + 1);
        out.append(base[0..pos]);
        out.push(r.rand_int(256) as u8);
        out.append(base[pos..base.len]);
    } else if kind == 2 {
        if base.len > 0 {
            let pos = r.rand_int(base.len);
            out.append(base[0..pos]);
            out.append(base[pos + 1..base.len]);
        } else {
            out.append(base);
        }
    } else {
        let other = pick_seed(r, pool, ends, max_len);
        let pos = r.rand_int(base.len + 1);
        let from = r.rand_int(other.len + 1);
        out.append(base[0..pos]);
        out.append(other[from..other.len]);
    }
    if out.len > max_len {
        out.resize(max_len);
    }
    return kind;
}
