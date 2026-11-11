// The coverage of a program that runs its work in parallel workers.
//
// It uses no fuzz run. It opens a bracket, lets four workers join it,
// and reads the edges that they reached together.
//
// Build:  goose build --debug examples/session.goose -o session
// Run:    ./session
// Build with GOOSE_CC set to the cov-cc script of the package to get the
// coverage. Without it the program prints "off".

import std;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "..";

struct Part {
    id: i64,
    sum: i64,
}

fn squares(n: i64) -> i64 {
    var s: i64 = 0;
    for i in n { s = s + i * i % 11; }
    return s;
}

fn digits(n: i64) -> i64 {
    var s: i64 = 0;
    var v: i64 = n;
    while v > 0 { s = s + v % 10; v = v / 10; }
    return s;
}

// Each worker attaches, does its work, and detaches before it ends.
thread_fn work_squares(n: i64) {
    fuzz::cov_attach();
    let s = squares(n);
    fuzz::cov_detach();
    qput(Part { id: 1, sum: s });
}

thread_fn work_digits(n: i64) {
    fuzz::cov_attach();
    let s = digits(n * 977);
    fuzz::cov_detach();
    qput(Part { id: 2, sum: s });
}

fn main() {
    fuzz::cov_reset();
    // The owner opens the bracket. It only waits, so it stops recording
    // before a worker attaches.
    fuzz::cov_begin();
    fuzz::cov_detach();
    let a = thread_spawn(work_squares, 50000);
    let b = thread_spawn(work_digits, 50000);
    let c = thread_spawn(work_squares, 20000);
    let d = thread_spawn(work_digits, 20000);
    // The owner joins every worker before it closes the bracket.
    thread_wait(a);
    thread_wait(b);
    thread_wait(c);
    thread_wait(d);
    let _ = fuzz::cov_end();
    var sum: i64 = 0;
    for k in 4 { let p = qget<Part>(); sum = sum + p.sum; }
    print("workers computed ", sum);
    if fuzz::cov_live() {
        print("live");
        print("edges reached by the workers: ", fuzz::cov_total());
        for c in 1..9 {
            print("  class ", c, ": ", fuzz::cov_class_edges(c));
        }
    } else {
        print("off");
    }
}
