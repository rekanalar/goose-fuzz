// The score of an input.
//
// The target gives the current input a score. The score rides the
// typed queue to the runner, because a global of a module is
// thread-local: a worker thread that writes a global is not seen by
// the thread that runs the fuzzer.
namespace fuzz;

struct Score {
    v: f64 = 0.0,
}

// The score of the last poll of this thread. The runner thread owns it.
var g_last: f64 = 0.0;

// Give the current input a score. The runner keeps the input with the
// highest score. One call per input.
fn score(v: f64) {
    qput(Score { v });
}

// Read the queue of the scores and give the last score of the input.
// The runner calls it after every run, so the queue holds no score of
// an older input.
fn poll_score() -> f64 {
    var s: f64 = 0.0;
    while true {
        let sc, got = qpoll<Score>();
        if !got {
            break;
        }
        s = sc.v;
    }
    g_last = s;
    return s;
}

// The score of the last input that this thread polled. Zero when no
// input carried a score.
fn last_score() -> f64 {
    return g_last;
}
