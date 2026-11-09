// The settings of one fuzz run.
namespace fuzz;

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
    // The corpus directory. The interesting inputs of a run go there,
    // and the next run takes them as seeds. Empty means fuzz/corpus.
    corpus_root: u8[..255] = [],
    // The program name of the child binary. Empty means the child mode
    // is refused.
    child: u8[..255] = [],
    // 0 picks one worker for each core, capped at 8. The valid range is
    // 1 to 15. The table of the process package holds 16.
    workers: i64 = 0,
    // The percent of mutations that use a token, from 0 to 100.
    token_rate: i64 = 25,
    // The dictionary text, in the libFuzzer format. Empty means no
    // dictionary. It holds at most 4096 bytes.
    dict: u8[..4096] = [],
    // The mutations that a seed of the pool may still get. A mutation
    // that reaches no new class spends one. The choice prefers the seeds
    // that have energy, and every seed gets its energy again when none
    // has any. 0 turns the spending off.
    seed_energy: i64 = 100,
    // The order of the pool. 0 takes the oldest seed first. 1 takes
    // the seed with the most new classes first.
    pool_order: i64 = 0,
    // The time of the probe of a stopped child, in milliseconds. The
    // probe runs the suspect input again in one child. 0 turns the
    // probe off, and every stop stays a hang.
    probe_ms: i64 = 30000,
    // The percent of the mutations that call the mutator of the
    // caller. 0 never calls it.
    mutator_rate: i64 = 10,
    // The score that steers the run. 0 uses the coverage only. 1 keeps
    // the input with the highest score of the target. 2 keeps the
    // slowest input, and the score is the time of the run.
    score_mode: i64 = 0,
}

fn config() -> Config {
    return Config { };
}
