// The settings of one fuzz run.
namespace fuzz;

import std;

struct Config {
    // 0 picks a fresh seed from random_seed(). Any other value repeats a run.
    seed: u64 = 0,
    // At least 0. 0 runs the seeds once and makes no mutation.
    runs: i64 = 10000,
    // 0 means no time limit. The run ends at the first limit.
    time_ms: i64 = 0,
    // At least 1. No mutated input is longer. A seed file is cut to it.
    max_len: i64 = 4096,
    // Empty means: start from the empty input.
    seed_dir: u8[..255] = [],
    // Empty means fuzz/crashers.
    crash_root: u8[..255] = [],
}

fn config() -> Config {
    return Config { };
}
