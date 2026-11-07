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

// The default of Config.token_rate, and of the child that gets no rate.
const DEFAULT_TOKEN_RATE = 25;

// Mutate like mutate_next, and use a token at the rate in percent. With
// an empty dictionary it calls mutate_next, so the rng draw order and
// the inputs stay byte-identical. With tokens it draws the rate roll,
// the token, the mode and the position after the four kinds. Returns
// the kind: 0 to 3 as mutate_next, 4 token insert, 5 token overwrite.
fn mutate_next_dict(r: rng&, pool: const u8[:], ends: const i64[:], max_len: i64,
                    dpool: const u8[:], dends: const i64[:], rate: i64, out: u8[>..]&) -> i64 {
    if dends.len == 0 {
        return mutate_next(r, pool, ends, max_len, out);
    }
    let kind = mutate_next(r, pool, ends, max_len, out);
    if rate <= 0 || r.rand_int(100) >= rate {
        return kind;
    }
    // The token is cut to max_len, so no input passes it.
    let tok = pick_seed(r, dpool, dends, max_len);
    if tok.len == 0 {
        return kind;
    }
    let mode = r.rand_int(2);
    if mode == 0 {
        // Insert the token at a position.
        let pos = r.rand_int(out.len + 1);
        var tmp: u8[>..] = [];
        tmp.append(out[0..pos]);
        tmp.append(tok);
        tmp.append(out[pos..out.len]);
        if tmp.len > max_len {
            tmp.resize(max_len);
        }
        out.clear();
        out.append(tmp);
        return 4;
    }
    // Write the token over input bytes.
    if out.len == 0 {
        return kind;
    }
    let pos = r.rand_int(out.len);
    let n = min(tok.len, out.len - pos);
    for i in 0..n {
        out[pos + i] = tok[i];
    }
    return 5;
}
