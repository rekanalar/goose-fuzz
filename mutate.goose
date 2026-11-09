// Mutate a seed into a new input.
//
// The pool holds one struct per seed, and the bytes of the seeds sit
// in one arena. A seed carries the mutations that it may still get,
// and the classes that it reached first.
namespace fuzz;

import std;

// One seed of the pool. The bytes live in the arena of the pool.
struct Seed {
    // The start of the bytes in the arena.
    off: i64 = 0,
    // The length of the bytes, before the cut of the limit.
    len: i64 = 0,
    // The mutations that the seed may still get. A mutation that
    // reaches no new class spends one. The choice prefers a seed that
    // has energy.
    energy: i64 = 0,
    // The classes that the seed reached first.
    hits: i64 = 0,
}

// The interesting values of one byte. A byte on one of these values
// sits on a border that programs test.
const INTERESTING: i64[11] = [0, 1, 16, 31, 32, 63, 64, 100, 127, 128, 255];

// The default of Config.seed_energy.
const DEFAULT_ENERGY = 100;

// The bytes of seed i, cut to max_len.
fn seed_at(pool: const u8[:], seeds: Seed[>..]&, i: i64, max_len: i64) -> const u8[:] {
    let s = seeds[i];
    var stop = s.len;
    if stop > max_len {
        stop = max_len;
    }
    return pool[s.off..s.off + stop];
}

// The index of the seed that a mutation works on, or -1 when the pool
// is empty. The order 0 takes the oldest seed that still has energy.
// The order 1 takes the seed with the most hits, and the oldest seed
// wins a tie.
fn pick_index(r: rng&, seeds: Seed[>..]&, order: i64) -> i64 {
    if seeds.len == 0 {
        return -1;
    }
    var at: i64 = -1;
    if order == 1 {
        var best: i64 = 0;
        for i in 0..seeds.len {
            if seeds[i].energy > 0 && seeds[i].hits > best {
                best = seeds[i].hits;
                at = i;
            }
        }
    }
    if at < 0 {
        for i in 0..seeds.len {
            if seeds[i].energy > 0 {
                at = i;
                break;
            }
        }
    }
    if at < 0 {
        at = r.rand_int(seeds.len);
    }
    return at;
}

// The length of a block that a block kind works on. Most blocks are
// small, and a few are large. The length never passes the limit.
fn choose_block_len(r: rng&, max_len: i64) -> i64 {
    let roll = r.rand_int(100);
    var lo: i64 = 1;
    var hi: i64 = 32;
    if roll >= 66 {
        lo = 32;
        hi = 128;
    }
    if roll >= 88 {
        lo = 128;
        hi = 1500;
    }
    if roll >= 97 {
        lo = 1500;
        hi = 32768;
    }
    var n = lo + r.rand_int(hi - lo + 1);
    if n > max_len {
        n = max_len;
    }
    if n < 1 {
        n = 1;
    }
    return n;
}

// Mutate the seed at the index at into out. An at of -1 starts from
// the empty input. Returns the kind.
fn mutate_at(r: rng&, pool: const u8[:], seeds: Seed[>..]&, at: i64, max_len: i64,
             out: u8[>..]&) -> i64 {
    var base: const u8[:] = pool[0..0];
    if at >= 0 {
        base = seed_at(pool, seeds, at, max_len);
    }
    return mutate_base(r, pool, base, seeds, max_len, out);
}

// Mutate the bytes of base into out. A second seed of the pool serves
// the kinds that copy or splice. Returns the kind.
fn mutate_base(r: rng&, pool: const u8[:], base: const u8[:], seeds: Seed[>..]&, max_len: i64,
               out: u8[>..]&) -> i64 {
    // The eighteen byte kinds carry the codes 0 to 3 and 6 to 19. The
    // pick runs over them in one order, and the codes 4 and 5 stay
    // free for the token kinds of the dictionary.
    let pick = r.rand_int(18);
    var kind: i64 = pick;
    if pick >= 4 {
        kind = pick + 2;
    }
    // An empty input has no byte to change. The mutation inserts a
    // block of random bytes instead, so the run still gets an input.
    if base.len == 0 {
        kind = 11;
    }
    // The bytes of a second seed, for the kinds that copy or splice.
    var other: const u8[:] = base;
    if seeds.len > 1 {
        let second = r.rand_int(seeds.len);
        other = seed_at(pool, seeds, second, max_len);
    }
    out.append(base);
    if kind == 0 {
        if base.len > 0 {
            let pos = r.rand_int(base.len);
            out[pos] = out[pos] ^ (1 << (r.rand_int(8) as u8));
        }
    } else if kind == 1 {
        let pos = r.rand_int(base.len + 1);
        var tmp: u8[>..] = [];
        tmp.append(base[0..pos]);
        tmp.push(r.rand_int(256) as u8);
        tmp.append(base[pos..base.len]);
        out.clear();
        out.append(tmp);
    } else if kind == 2 {
        if base.len > 0 {
            let pos = r.rand_int(base.len);
            var tmp: u8[>..] = [];
            tmp.append(base[0..pos]);
            tmp.append(base[pos + 1..base.len]);
            out.clear();
            out.append(tmp);
        }
    } else if kind == 3 {
        let pos = r.rand_int(base.len + 1);
        let from = r.rand_int(other.len + 1);
        var tmp: u8[>..] = [];
        tmp.append(base[0..pos]);
        tmp.append(other[from..other.len]);
        out.clear();
        out.append(tmp);
    } else if kind == 6 {
        // Flip the eight bits of one byte.
        if base.len > 0 {
            let pos = r.rand_int(base.len);
            out[pos] = out[pos] ^ 255;
        }
    } else if kind == 7 {
        // Set one byte to an interesting value.
        if base.len > 0 {
            let pos = r.rand_int(base.len);
            out[pos] = INTERESTING[r.rand_int(11)] as u8;
        }
    } else if kind == 8 {
        // Add one to one byte, or take one from it.
        if base.len > 0 {
            let pos = r.rand_int(base.len);
            if r.rand_int(2) == 0 {
                out[pos] = out[pos] + 1;
            } else {
                out[pos] = out[pos] - 1;
            }
        }
    } else if kind == 9 {
        // Add an interesting value to one byte, or take it from it.
        if base.len > 0 {
            let pos = r.rand_int(base.len);
            let v = INTERESTING[r.rand_int(11)] as u8;
            if r.rand_int(2) == 0 {
                out[pos] = out[pos] + v;
            } else {
                out[pos] = out[pos] - v;
            }
        }
    } else if kind == 10 {
        // Swap two bytes.
        if base.len > 1 {
            let a = r.rand_int(base.len);
            var b = r.rand_int(base.len);
            while b == a {
                b = r.rand_int(base.len);
            }
            let t = out[a];
            out[a] = out[b];
            out[b] = t;
        }
    } else if kind == 11 {
        // Insert a block of bytes. The block comes from another seed,
        // and it holds random bytes when the pool holds no other seed.
        let n = choose_block_len(r, max_len);
        let pos = r.rand_int(base.len + 1);
        var tmp: u8[>..] = [];
        tmp.append(base[0..pos]);
        if other.len > 0 {
            let from = r.rand_int(other.len + 1);
            var stop = from + n;
            if stop > other.len {
                stop = other.len;
            }
            tmp.append(other[from..stop]);
        } else {
            for i in 0..n {
                tmp.push(r.rand_int(256) as u8);
            }
        }
        tmp.append(base[pos..base.len]);
        out.clear();
        out.append(tmp);
    } else if kind == 12 {
        // Delete a block of bytes.
        if base.len > 1 {
            let n = choose_block_len(r, base.len - 1);
            let pos = r.rand_int(base.len - 1);
            var stop = pos + n;
            if stop > base.len {
                stop = base.len;
            }
            var tmp: u8[>..] = [];
            tmp.append(base[0..pos]);
            tmp.append(base[stop..base.len]);
            out.clear();
            out.append(tmp);
        }
    } else if kind == 13 {
        // Write one byte over the input.
        if base.len > 0 {
            let pos = r.rand_int(base.len);
            out[pos] = r.rand_int(256) as u8;
        }
    } else if kind == 14 {
        // Write a block of bytes of another seed over the input.
        if base.len > 0 {
            let n = choose_block_len(r, base.len);
            let pos = r.rand_int(base.len);
            let from = r.rand_int(other.len + 1);
            var stop = from + n;
            if stop > other.len {
                stop = other.len;
            }
            var k = pos;
            var j = from;
            while k < out.len && j < stop {
                out[k] = other[j];
                k += 1;
                j += 1;
            }
        }
    } else if kind == 15 {
        // Copy a block of the input to another place of the input.
        if base.len > 0 {
            let n = choose_block_len(r, base.len);
            let from = r.rand_int(base.len);
            var fstop = from + n;
            if fstop > base.len {
                fstop = base.len;
            }
            let pos = r.rand_int(base.len + 1);
            var tmp: u8[>..] = [];
            tmp.append(base[0..pos]);
            tmp.append(base[from..fstop]);
            tmp.append(base[pos..base.len]);
            out.clear();
            out.append(tmp);
        }
    } else if kind == 16 {
        // Copy a block of the input to the end of the input.
        if base.len > 0 {
            let n = choose_block_len(r, base.len);
            let from = r.rand_int(base.len);
            var fstop = from + n;
            if fstop > base.len {
                fstop = base.len;
            }
            out.append(base[from..fstop]);
        }
    } else if kind == 17 {
        // Shuffle the bytes of the input.
        if base.len > 1 {
            let from = r.rand_int(base.len);
            let n = choose_block_len(r, base.len - from);
            for i in 0..n - 1 {
                let j = i + r.rand_int(n - i);
                let t = out[from + i];
                out[from + i] = out[from + j];
                out[from + j] = t;
            }
        }
    } else if kind == 18 {
        // Change a number that stands in the text.
        change_text_number(r, out);
    } else {
        // Change a number of two, four or eight bytes.
        change_binary_number(r, out);
    }
    if out.len > max_len {
        out.resize(max_len);
    }
    return kind;
}

// Append one mutated input to out. Picks the seed in the order of the
// pool, and mutates it. Returns the kind. src holds the index of the
// seed, or -1 when the pool was empty. All choices come from r, so a
// seed repeats a run.
fn mutate_next(r: rng&, pool: const u8[:], seeds: Seed[>..]&, max_len: i64, order: i64,
               out: u8[>..]&, src: i64&) -> i64 {
    let at = pick_index(r, seeds, order);
    src = at;
    return mutate_at(r, pool, seeds, at, max_len, out);
}

// Find a run of digits in out, and rewrite the number. The rolls are
// the add of one, the take of one, the double, the half and a random
// value. An input without digits stays as it is.
fn change_text_number(r: rng&, out: u8[>..]&) {
    var start: i64 = -1;
    var stop: i64 = -1;
    for i in 0..out.len {
        let d = out[i];
        if d >= 48 && d <= 57 {
            if start < 0 {
                start = i;
            }
            stop = i + 1;
        } else if start >= 0 {
            break;
        }
    }
    if start < 0 {
        return;
    }
    var value: i64 = 0;
    for i in start..stop {
        value = value * 10 + (out[i] - 48);
    }
    let roll = r.rand_int(5);
    if roll == 0 {
        value += 1;
    } else if roll == 1 {
        value -= 1;
    } else if roll == 2 {
        value *= 2;
    } else if roll == 3 {
        value /= 2;
    } else {
        value = r.rand_int(1000000);
    }
    if value < 0 {
        value = 0;
    }
    // Write the new number over the old one, and move the tail when
    // the number holds other digits than before.
    var digits: u8[>..] = [];
    if value == 0 {
        digits.push(48);
    }
    while value > 0 {
        digits.push((48 + (value % 10)) as u8);
        value /= 10;
    }
    var tmp: u8[>..] = [];
    tmp.append(out[0..start]);
    tmp.append(digits);
    tmp.append(out[stop..out.len]);
    out.clear();
    out.append(tmp);
}

// Change a number of two, four or eight bytes. The roll picks the
// width, the byte order and the change. An input shorter than two
// bytes stays as it is.
fn change_binary_number(r: rng&, out: u8[>..]&) {
    if out.len < 2 {
        return;
    }
    let widths: i64[3] = [2, 4, 8];
    let w = widths[r.rand_int(3)];
    if out.len < w {
        return;
    }
    let pos = r.rand_int(out.len - w + 1);
    let little = r.rand_int(2) == 0;
    var v: u64 = 0;
    for i in 0..w {
        let b = out[pos + i] as u64;
        if little {
            v |= b << (8 * i);
        } else {
            v |= b << (8 * (w - 1 - i));
        }
    }
    let roll = r.rand_int(4);
    if roll == 0 {
        v += 1;
    } else if roll == 1 {
        v -= 1;
    } else if roll == 2 {
        v = ~v;
    } else {
        v = (INTERESTING[r.rand_int(11)] as u64) * 257;
    }
    for i in 0..w {
        let shift = if little { 8 * i } else { 8 * (w - 1 - i) };
        out[pos + i] = ((v >> shift) & 255) as u8;
    }
}

// The default mutator. It never writes, so the runner uses a kind of
// its own table. The mutator of the caller takes this shape too.
fn no_mutator(data: const u8[:], out: u8[>..]&) -> bool {
    if data.len > 0 && out.len > 0 {
        return false;
    }
    return false;
}

// The default of Config.token_rate, and of the child that gets no rate.
const DEFAULT_TOKEN_RATE = 25;

// Write a token of the dictionary into out at the rate in percent.
// Returns 4 for an insert, 5 for an overwrite, and -1 when no token
// was written. The draws come after the draws of the byte kinds.
fn apply_token(r: rng&, dpool: const u8[:], dends: const i64[:], rate: i64, max_len: i64,
                out: u8[>..]&) -> i64 {
    if dends.len == 0 {
        return -1;
    }
    if rate <= 0 || r.rand_int(100) >= rate {
        return -1;
    }
    // The token is cut to max_len, so no input passes it.
    let ti = r.rand_int(dends.len);
    var tstart: i64 = 0;
    if ti > 0 {
        tstart = dends[ti - 1];
    }
    var tstop = dends[ti];
    if tstop - tstart > max_len {
        tstop = tstart + max_len;
    }
    let tok = dpool[tstart..tstop];
    if tok.len == 0 {
        return -1;
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
        return -1;
    }
    let pos = r.rand_int(out.len);
    let n = min(tok.len, out.len - pos);
    for i in 0..n {
        out[pos + i] = tok[i];
    }
    return 5;
}

// Mutate like mutate_next, and use a token at the rate in percent. With
// an empty dictionary it calls mutate_next, so the rng draw order and
// the inputs stay byte-identical. With tokens it draws the rate roll,
// the token, the mode and the position after the byte kinds. Returns
// the kind: the codes of mutate_next, 4 token insert, 5 token
// overwrite. src holds the seed index, or -1.
fn mutate_next_dict(r: rng&, pool: const u8[:], seeds: Seed[>..]&, max_len: i64, order: i64,
                    dpool: const u8[:], dends: const i64[:], rate: i64, out: u8[>..]&,
                    src: i64&) -> i64 {
    if dends.len == 0 {
        return mutate_next(r, pool, seeds, max_len, order, out, src);
    }
    let kind = mutate_next(r, pool, seeds, max_len, order, out, src);
    let tk = apply_token(r, dpool, dends, rate, max_len, out);
    if tk < 0 {
        return kind;
    }
    return tk;
}
