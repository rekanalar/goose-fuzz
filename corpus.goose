// Seed files and crasher files.
namespace fuzz;

import std;
import os;

// Read every file of dir, in name order, into pool. ends[i] is the end
// offset of file i. A file is cut to max_len. Returns the number of files,
// or -1 when dir cannot be listed.
fn load_seeds(dir: const u8[:], max_len: i64, pool: u8[>..]&, ends: i64[>..]&) -> i64 {
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
                ends.push(pool.len);
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

// Save input as <root>/<name>/<hex of its hash>. The same input always gets
// the same file, and an existing file stays. Returns false on a write error.
fn save_crasher(root: const u8[:], name: const u8[:], input: const u8[:]) -> bool {
    var dir: u8[>..] = [];
    crash_dir(root, name, dir);
    // make_dir makes one level, so make each level in turn
    for i in 1..dir.len {
        if dir[i] == '/' {
            make_dir(dir[0..i]);
        }
    }
    if !make_dir(dir) {
        return false;
    }
    dir.append("/");
    hex16(dir, fnv1a64(input));
    if file_exists(dir) {
        return true;
    }
    return write_file(dir, input);
}
