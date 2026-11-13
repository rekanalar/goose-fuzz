// The scratch directories of the fuzz tests.
namespace work_dirs;

import std;
import os;

// A scratch directory under TMPDIR for one test.
fn scratch(name: const u8[:], out: u8[>..]&) {
    env("TMPDIR", out);
    assert(out.len > 0);
    out.append("/");
    out.append(name);
    make_dir(out);
}


// Delete every file of dir, then dir.
fn clean_dir(dir: const u8[:]) {
    var names: u8[>..] = [];
    if !list_dir(dir, names) {
        return;
    }
    var pos: i64 = 0;
    while pos < names.len {
        var stop = find(names[pos..names.len], "\n");
        if stop < 0 {
            stop = names.len - pos;
        }
        if stop > 0 {
            var p: u8[>..] = [];
            p.append(dir);
            p.append("/");
            p.append(names[pos..pos + stop]);
            delete_file(p);
        }
        pos += stop + 1;
    }
    delete_dir(dir);
}
