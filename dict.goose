// The dictionary of the mutator.
//
// The text sits in Config.dict, in the libFuzzer format. A line is
// "value" or name="value". A line that starts with # is a comment. A
// blank line is ignored. The escapes \\, \" and \xNN decode inside the
// quotes.
namespace fuzz;

import std;
import os;

// Parse the dictionary text into the token pool. ends[i] is the end
// offset of token i. Returns the count of tokens, or -1 after it filled
// err with "line N: the reason". The tokens before a bad line stay in
// the pool, so a lenient caller keeps them.
fn dict_parse(text: const u8[:], dpool: u8[>..]&, dends: i64[>..]&, err: u8[>..]&) -> i64 {
    var n: i64 = 0;
    var line: i64 = 0;
    var pos: i64 = 0;
    while pos < text.len {
        // The bytes of one line, without its newline.
        var stop = find(text[pos..text.len], "\n");
        if stop < 0 {
            stop = text.len - pos;
        }
        line += 1;
        let raw = text[pos..pos + stop];
        pos += stop + 1;
        let s = trim(raw);
        if s.len == 0 || s[0] == '#' {
            continue;
        }
        // The value starts at the first quote. Text before it is a name
        // that ends at an equals sign.
        let q = find(s, "\"");
        if q < 0 {
            return dict_fail(err, line, "no quote");
        }
        if q > 0 && s[q - 1] != '=' {
            return dict_fail(err, line, "text before the quote");
        }
        var tok: u8[>..] = [];
        var bad: u8[>..] = [];
        let end = decode_value(s[q + 1..s.len], tok, bad);
        if end < 0 {
            return dict_fail(err, line, bad);
        }
        // Only spaces may follow the closing quote.
        let tail = trim(s[q + 1 + end..s.len]);
        if tail.len > 0 {
            return dict_fail(err, line, "text after the quote");
        }
        dpool.append(tok);
        dends.push(dpool.len);
        n += 1;
    }
    return n;
}

// Fill err with the line number and the reason. Returns -1, so the
// caller can return it.
fn dict_fail(err: u8[>..]&, line: i64, reason: const u8[:]) -> i64 {
    err.clear();
    err.append("line ");
    format_int(err, line, 10, 0, ' ');
    err.append(": ");
    err.append(reason);
    return -1;
}

// Decode the bytes from the opening quote to the closing quote into tok.
// Returns the offset just past the closing quote, or -1 with the reason
// in bad. The escapes are \\, \" and \xNN.
fn decode_value(s: const u8[:], tok: u8[>..]&, bad: u8[>..]&) -> i64 {
    var i: i64 = 0;
    while i < s.len {
        let b = s[i];
        if b == '"' {
            return i + 1;
        }
        if b != '\\' {
            tok.push(b);
            i += 1;
            continue;
        }
        if i + 1 >= s.len {
            bad.append("the escape ends the line");
            return -1;
        }
        let e = s[i + 1];
        if e == '\\' {
            tok.push('\\');
            i += 2;
        } else if e == '"' {
            tok.push('"');
            i += 2;
        } else if e == 'x' {
            if i + 3 >= s.len {
                bad.append("the \\xNN escape is short");
                return -1;
            }
            let v, ok = parse_int(s[i + 2..i + 4], 16);
            if !ok || v < 0 || v > 255 {
                bad.append("the \\xNN digits are bad");
                return -1;
            }
            tok.push(v as u8);
            i += 4;
        } else {
            bad.append("the escape is unknown");
            return -1;
        }
    }
    bad.append("the quote never closes");
    return -1;
}

// Append one token to cfg.dict as a quoted, escaped line. Returns false
// when the token is empty or the text would pass the capacity.
fn dict_add(cfg: Config&, token: const u8[:]) -> bool {
    if token.len == 0 {
        return false;
    }
    var line: u8[>..] = [];
    line.push('"');
    for b in token {
        if b == '\\' {
            line.append("\\\\");
        } else if b == '"' {
            line.append("\\\"");
        } else if b < 32 || b > 126 {
            line.append("\\x");
            format_uint(line, b, 16, 2, '0');
        } else {
            line.push(b);
        }
    }
    line.push('"');
    line.push('\n');
    if cfg.dict.len + line.len > cfg.dict.cap {
        return false;
    }
    cfg.dict.append(line);
    return true;
}

// Read a dictionary file, check every line, and append the text to
// cfg.dict. A bad line fills err with the line number and appends
// nothing. Returns false on a bad line, a read error, or a full buffer.
fn dict_load(cfg: Config&, path: const u8[:], err: u8[>..]&) -> bool {
    var text: u8[>..] = [];
    if !read_file(path, text) {
        err.clear();
        err.append("the file cannot be read");
        return false;
    }
    // The text has to fit in the config, so a bigger file is refused
    // before it is parsed.
    if cfg.dict.len + text.len > cfg.dict.cap {
        err.clear();
        err.append("the dictionary text is full");
        return false;
    }
    var dpool: u8[>..] = [];
    var dends: i64[>..] = [];
    let n = dict_parse(text, dpool, dends, err);
    if n < 0 {
        return false;
    }
    cfg.dict.append(text);
    return true;
}
