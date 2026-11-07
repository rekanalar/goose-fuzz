// A reader over a byte input.
//
// The mutator makes bytes. A target that wants values reads them from a
// Reader. No read fails: a read past the end gives the default of its
// type. The same bytes give the same values in every run, so a saved
// crasher replays.
namespace fuzz;

import std;

// The input bytes and the cursor. The slice field holds no default, so
// the caller builds the struct with Reader { data: data }.
struct Reader {
    data: const u8[:],
    pos: i64 = 0,
}

// Build a reader over the bytes.
fn reader(data: const u8[:]) -> Reader {
    return Reader { data: data };
}

// n bytes at pos, big-endian, as a number.
fn be_bytes(data: const u8[:], pos: i64, n: i64) -> u64 {
    var v: u64 = 0;
    for i in 0..n {
        v = (v << 8) | data[pos + i];
    }
    return v;
}

// One byte as a bool. The default is false.
fn read_bool(r: Reader&) -> bool {
    if r.pos >= r.data.len {
        return false;
    }
    let v = r.data[r.pos] != 0;
    r.pos += 1;
    return v;
}

// Eight bytes, big-endian, mapped into [lo, hi] by modulo. Bytes that
// the input does not hold count as 0. Past the end the default is 0.
// A range with the low bound above the high bound is refused: the read
// returns 0 and consumes nothing.
fn read_i64(r: Reader&, lo: i64, hi: i64) -> i64 {
    if lo > hi {
        return 0;
    }
    if r.pos >= r.data.len {
        return 0;
    }
    let n = min(8, r.data.len - r.pos);
    let v = be_bytes(r.data, r.pos, n);
    r.pos += n;
    // The width of the range, built without a negative as conversion,
    // because the debug build checks every as.
    var width: u64 = 0;
    if lo >= 0 || hi <= 0 {
        width = ((hi - lo) as u64) + 1;
    } else if lo > -4611686018427387904 {
        width = ((0 - lo) as u64) + (hi as u64) + 1;
    } else {
        width = 4611686018427387904;
    }
    let off = (v % width) as i64;
    return lo + off;
}

// Up to max_len bytes from the cursor. The default is the empty string.
fn read_string(r: Reader&, max_len: i64) -> u8[>..] {
    var out: u8[>..] = [];
    if r.pos >= r.data.len || max_len <= 0 {
        return out;
    }
    let n = min(max_len, r.data.len - r.pos);
    out.append(r.data[r.pos..r.pos + n]);
    r.pos += n;
    return out;
}

// One count byte, then 8 bytes per item, at most max_items. The list
// holds the items that the bytes give. The default is the empty list.
fn read_i64_list(r: Reader&, max_items: i64) -> i64[>..] {
    var out: i64[>..] = [];
    if r.pos >= r.data.len || max_items <= 0 {
        return out;
    }
    let want = min(r.data[r.pos] as i64, max_items);
    r.pos += 1;
    while out.len < want && r.pos + 8 <= r.data.len {
        let v = be_bytes(r.data, r.pos, 8);
        // The top bit goes away, because the debug build checks the as
        // conversion. The items are nonnegative.
        out.push((v & 9223372036854775807) as i64);
        r.pos += 8;
    }
    return out;
}
