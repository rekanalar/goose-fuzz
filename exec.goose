// Run one input in a contained worker.
//
// The input crosses to the worker through a typed queue, because a worker
// argument cannot hold a slice.
namespace fuzz;

import std;

struct Input {
    data: u8[>..] = [],
}

// Call this in the target thread_fn: it takes the input and calls F on it.
fn call<F>() {
    let inp = qget<Input>();
    F(inp.data);
}

// Like call, for a typed target. F takes the Reader over the input
// bytes. The crasher stays the raw bytes.
fn call_typed<F>() {
    let inp = qget<Input>();
    var r = reader(inp.data);
    F(r);
}

// Remove inputs that a target did not take.
fn drain() {
    while true {
        let _, got = qpoll<Input>();
        if !got {
            return;
        }
    }
}

// Run W on one input. Returns false and appends the abort message to why.
fn run_one<W>(input: const u8[:], why: u8[>..]&) -> bool {
    drain();
    var buf: u8[>..] = [];
    buf.append(input);
    qput(Input { copy(buf) });
    let id = thread_spawn_contained(W);
    let ok = thread_wait(id, why);
    drain();
    return ok;
}

// Like call, for a law F(d) -> bool. A false result aborts with "law failed".
fn call_law<F>() {
    let inp = qget<Input>();
    if !F(inp.data) {
        abort("law failed");
    }
}
