// The thread test of the coverage layer.
//
// Build and run: goose build --debug test/threads.goose -o <file>, then run <file>.
// Build it with GOOSE_CC set to the cov-cc script of the package for a
// coverage build. A program with threads needs goose build, because goose
// run refuses it.
//
// The program prints "live" when the coverage works and "off" when it does
// not. The gate reads that word.

import std;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "..";

struct Done {
    id: i64,
    sum: i64,
}

// Four pieces of code that differ, so each worker reaches edges that the
// others do not reach.
fn code_a(n: i64) -> i64 {
    var s: i64 = 0;
    for i in n { s = s + (i * 3) % 7; }
    return s;
}

fn code_b(n: i64) -> i64 {
    var s: i64 = 1;
    for i in n { s = (s ^ i) + 5; if s > 100000 { s = s - 99999; } }
    return s;
}

fn code_c(n: i64) -> i64 {
    var s: i64 = 0;
    for i in n {
        if i % 3 == 0 { s = s + 1; } else if i % 3 == 1 { s = s + 2; } else { s = s + 4; }
    }
    return s;
}

fn code_d(n: i64) -> i64 {
    var s: i64 = 0;
    var v: i64 = n;
    while v > 0 { s = s + v % 10; v = v / 10; }
    return s + n;
}

// Code that only the unattached worker runs.
fn code_u(n: i64) -> i64 {
    var s: i64 = 7;
    for i in n { s = (s * 31 + i) % 1000003; }
    return s;
}

// The loop of the eight workers that run the same code.
fn spin(n: i64, k: i64) -> i64 {
    var s: i64 = 0;
    for i in n { s = s + (i * k) % 7; }
    return s;
}

thread_fn wa(n: i64) { fuzz::cov_attach(); let s = code_a(n); fuzz::cov_detach(); qput(Done { id: 1, sum: s }); }
thread_fn wb(n: i64) { fuzz::cov_attach(); let s = code_b(n); fuzz::cov_detach(); qput(Done { id: 2, sum: s }); }
thread_fn wc(n: i64) { fuzz::cov_attach(); let s = code_c(n); fuzz::cov_detach(); qput(Done { id: 3, sum: s }); }
thread_fn wd(n: i64) { fuzz::cov_attach(); let s = code_d(n); fuzz::cov_detach(); qput(Done { id: 4, sum: s }); }
// The worker that never attaches.
thread_fn wu(n: i64) { let s = code_u(n); qput(Done { id: 5, sum: s }); }
thread_fn wspin(k: i64) { fuzz::cov_attach(); let s = spin(20000, k); fuzz::cov_detach(); qput(Done { id: 6, sum: s }); }
// The worker that aborts while it records. A contained abort ends it.
thread_fn wabort(n: i64) {
    fuzz::cov_attach();
    let s = code_a(n);
    if s > 0 { abort("test abort"); }
    fuzz::cov_detach();
    qput(Done { id: 7, sum: s });
}

// snapshot appends the counts of the layer: the edges, the lost
// addresses and the classes 1 to 8.
fn snapshot(out: i64[>..]&) {
    out.push(fuzz::cov_total() as i64);
    out.push(fuzz::cov_lost() as i64);
    for c in 1..9 { out.push(fuzz::cov_class_edges(c) as i64); }
}

// session runs one bracket with workers of the kind that mode names.
//   0 no worker, the owner alone
//   1 four attached workers
//   2 four attached workers and one that never attaches
//   3 eight attached workers that run the same code
//   4 four attached workers and one that aborts
// It gives the sum of the results of the workers and fills snap.
fn session(mode: i64, snap: i64[>..]&) -> i64 {
    fuzz::cov_reset();
    fuzz::cov_begin();
    // The owner only waits, so it stops recording. Its waiting loop would
    // add counts that depend on the speed of the machine.
    fuzz::cov_detach();
    var ids: i64[>..] = [];
    var expect: i64 = 0;
    if mode == 1 || mode == 2 || mode == 4 {
        ids.push(thread_spawn(wa, 3000));
        ids.push(thread_spawn(wb, 3000));
        ids.push(thread_spawn(wc, 3000));
        ids.push(thread_spawn(wd, 3000));
        expect = 4;
    }
    if mode == 2 {
        ids.push(thread_spawn(wu, 3000));
        expect = expect + 1;
    }
    if mode == 3 {
        for k in 8 { ids.push(thread_spawn(wspin, k + 1)); }
        expect = 8;
    }
    for id in ids { assert(thread_wait(id)); }
    if mode == 4 {
        var why: u8[>..] = [];
        assert(!thread_wait(thread_spawn_contained(wabort, 3000), why));
        assert(why.len > 0);
    }
    var total: i64 = 0;
    for k in expect { let d = qget<Done>(); total = total + d.sum; }
    let _ = fuzz::cov_end();
    snapshot(snap);
    return total;
}

fn main() {
    var owner: i64[>..] = [];
    let s0 = session(0, owner);
    assert(s0 == 0);

    var four: i64[>..] = [];
    let s1 = session(1, four);
    // The workers compute the same sums as one thread does.
    assert(s1 == code_a(3000) + code_b(3000) + code_c(3000) + code_d(3000));

    var four_again: i64[>..] = [];
    let s1b = session(1, four_again);
    assert(s1b == s1);

    var with_u: i64[>..] = [];
    let s2 = session(2, with_u);
    assert(s2 == s1 + code_u(3000));

    var eight: i64[>..] = [];
    let s3 = session(3, eight);
    var want: i64 = 0;
    for k in 8 { want = want + spin(20000, k + 1); }
    assert(s3 == want);

    var after_abort: i64[>..] = [];
    let s4 = session(4, after_abort);
    assert(s4 == s1);

    if fuzz::cov_live() {
        print("live");
        // The attached workers add edges beyond the owner alone.
        assert(four[0] > owner[0]);
        // Two runs after a reset give the same counts.
        assert(four == four_again);
        // A worker that never attaches adds nothing.
        assert(with_u == four);
        // The table has room for all of it.
        assert(four[1] == 0 && eight[1] == 0);
        // Many threads give the same classes in every repetition.
        for rep in 20 {
            var again: i64[>..] = [];
            let s = session(3, again);
            assert(s == want);
            assert(again == eight);
        }
        // An abort in an attached worker holds no lock. The run goes on
        // and a later run gives the counts of the earlier one.
        assert(after_abort[0] >= four[0]);
        var later: i64[>..] = [];
        let _ = session(1, later);
        assert(later == four);
    } else {
        print("off");
        // Without the coverage compiler the layer records nothing, and
        // attach and detach have no effect.
        assert(four[0] == 0 && eight[0] == 0 && owner[0] == 0);
        assert(four == owner);
        assert(!fuzz::cov_live());
    }
    print("threads test passed");
    return 0;
}
