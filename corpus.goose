// Seed files and crasher files.
namespace fuzz;

import std;
import os;

// The cap of the files of one corpus directory. A run writes no file
// past the cap.
const CORPUS_MAX = 4096;

// Read every file of dir, in name order, into pool. One Seed struct per
// file holds the offset, the length and the energy. A file is cut to
// max_len. Returns the number of files, or -1 when dir cannot be listed.
fn load_seeds(dir: const u8[:], max_len: i64, energy: i64, pool: u8[>..]&, seeds: Seed[>..]&) -> i64 {
    var names: u8[>..] = [];
    if !list_dir(dir, names) {
        return -1;
    }
    var n: i64 = 0;
    var pos: i64 = 0;
    while pos < names.len {
        var stop = find(names[pos..names.len], "\n");
        if stop < 0 {
            stop = names.len - pos;
        }
        if stop > 0 {
            var path: u8[>..] = [];
            path.append(dir);
            path.append("/");
            path.append(names[pos..pos + stop]);
            var data: u8[>..] = [];
            if read_file(path, data) {
                if data.len > max_len {
                    data.resize(max_len);
                }
                pool.append(data);
                var s = Seed { };
                s.off = pool.len - data.len;
                s.len = data.len;
                s.energy = energy;
                s.hits = 0;
                seeds.push(s);
                n += 1;
            }
        }
        pos += stop + 1;
    }
    return n;
}

// Append the crasher directory of name: <root>/<name>. An empty root means
// fuzz/crashers.
fn crash_dir(root: const u8[:], name: const u8[:], out: u8[>..]&) {
    if root.len == 0 {
        out.append("fuzz/crashers");
    } else {
        out.append(root);
    }
    out.append("/");
    out.append(name);
}

// Append the corpus directory of name: <root>/<name>. An empty root means
// fuzz/corpus.
fn corpus_dir(root: const u8[:], name: const u8[:], out: u8[>..]&) {
    if root.len == 0 {
        out.append("fuzz/corpus");
    } else {
        out.append(root);
    }
    out.append("/");
    out.append(name);
}

// The files of the corpus directory of name, into pool. A directory that
// does not exist holds no files and is not an error. Returns the count
// of the files.
fn load_corpus(root: const u8[:], name: const u8[:], max_len: i64, energy: i64,
               pool: u8[>..]&, seeds: Seed[>..]&) -> i64 {
    var dir: u8[>..] = [];
    corpus_dir(root, name, dir);
    if !is_dir(dir) {
        return 0;
    }
    let n = load_seeds(dir, max_len, energy, pool, seeds);
    if n < 0 {
        return 0;
    }
    return n;
}

// Save input as <root>/<name>/<hex of its hash>. The same input always gets
// the same file, and an existing file stays. Returns false on a write error.
fn save_crasher(root: const u8[:], name: const u8[:], input: const u8[:]) -> bool {
    var dir: u8[>..] = [];
    crash_dir(root, name, dir);
    return save_in_dir(dir, input) >= 0;
}

// Save input as a file of the corpus of name. The name of the file is the
// hash of the input, so the same input always gets the same file.
// Returns 1 when it made the file, 0 when the file was there, and -1 on a
// write error.
fn save_corpus(root: const u8[:], name: const u8[:], input: const u8[:]) -> i64 {
    var dir: u8[>..] = [];
    corpus_dir(root, name, dir);
    return save_in_dir(dir, input);
}

// Save input in dir, under the name of its hash. The same input always
// gets the same file, and an existing file stays. Returns 1 when it made
// the file, 0 when the file was there, and -1 on a write error.
fn save_in_dir(dir: const u8[:], input: const u8[:]) -> i64 {
    var path: u8[>..] = [];
    path.append(dir);
    // make_dir makes one level, so make each level in turn
    for i in 1..dir.len {
        if dir[i] == '/' {
            make_dir(dir[0..i]);
        }
    }
    if !make_dir(dir) {
        return -1;
    }
    path.append("/");
    hex16(path, fnv1a64(input));
    if file_exists(path) {
        return 0;
    }
    if write_file(path, input) {
        return 1;
    }
    return -1;
}
