# goose-fuzz

[![ci](https://github.com/rekanalar/goose-fuzz/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-fuzz/actions/workflows/ci.yml)

Fuzzing for Goose programs: seeded mutation, crash isolation, replay and
shrinking. It is pure Goose and uses the standard library only. It works
with Goose v2026.3 and v2026.4.

The package runs your function on many mutated byte inputs. Each run happens
in a contained worker. An abort ends only that run. The abort becomes a
finding with its message and its source line, and the run goes on.

## Install

Add this to the root file of the program that uses it:

```goose
import fuzz from "rekanalar/goose-fuzz@v0.1.0";
```

The CI runs the gate on Linux, macOS and Windows. It uses Goose v2026.3 and
v2026.4 on each.

## Use

Write a function that takes a byte slice. Write one `thread_fn` line that
hands it to the package. Call `fuzz::run`.

```goose
import std;
import fuzz from "rekanalar/goose-fuzz@v0.1.0";

fn parse(d: const u8[:]) { /* may abort */ }

thread_fn target() { fuzz::call(parse); }

fn main() {
    var cfg = fuzz::config();
    cfg.runs = 5000;
    var rep = fuzz::Report { };
    let found = fuzz::run("parse", cfg, rep, target);
    var out: u8[>..] = [];
    fuzz::format_report(out, rep);
    print(out);
    if found != 0 || rep.save_failed > 0 {
        exit(1);
    }
    return 0;
}
```

Goose does not allow a generic `thread_fn`, so you write the one line yourself. The
worker name is always the last argument.

See `examples/parser.goose` for a complete program.

## Build and run

A worker is a thread. Threads need a C compiler. `goose run` refuses a
threaded program and prints "JIT mode does not support threads yet". So build
the program, then run the file:

```sh
goose build --debug your_fuzzer.goose -o your_fuzzer
./your_fuzzer
```

Use `--debug`. It makes an integer overflow abort, so the fuzzer can find it.
This is the one place where this package does not use `goose run`.

A `return` from `main` does not set the exit code of a built program. Call
`exit(1)` to fail a gate.

## API

| Function | Purpose |
|---|---|
| `fuzz::call(F)` | Call in the target `thread_fn`. Takes the input and calls `F` on it. |
| `fuzz::call_law(F)` | As `call`, for `F(d) -> bool`. A false result aborts with `law failed`. |
| `fuzz::config()` | A `Config` with the defaults. |
| `fuzz::run(name, cfg, rep, W)` | Fuzz the worker `W`. Fills `rep`. Returns the finding count, or -1 when the seed directory cannot be read. |
| `fuzz::replay(name, crash_root, rep, W)` | Run every saved crasher once. Returns the number that aborted. Passed files: `rep.runs` minus that. |
| `fuzz::run_one(input, why, W)` | Run one input. Returns false and fills `why` when it aborts. |
| `fuzz::shrink(input, out, W)` | Fill `out` with a shorter input that aborts at the same site. Returns false when `input` does not abort. |
| `fuzz::format_report(out, rep)` | Append a text report. |
| `fuzz::finding_count(rep)` | The number of findings. |
| `fuzz::finding_site(rep, i)` | The `file:line` of finding `i`. |
| `fuzz::finding_message(rep, i)` | The first abort message at that site. |
| `fuzz::finding_input(rep, i)` | The first input that reached that site. |
| `fuzz::finding_hits(rep, i)` | The number of runs that reached that site. |

### Config

| Field | Default | Meaning |
|---|---|---|
| `seed` | 0 | 0 picks a fresh seed. Any other value repeats a run. |
| `runs` | 10000 | The run count. 0 runs the seeds once and makes no mutation. |
| `time_ms` | 0 | The time limit. 0 means none. The run ends at the first limit. |
| `max_len` | 4096 | No input is longer. A seed file is cut to this length. |
| `seed_dir` | empty | A directory of seed files. Empty starts from the empty input. |
| `crash_root` | empty | The crasher root. Empty means `fuzz/crashers`. |

The run records the seed in `rep.seed`. `format_report` prints it. Pass it
back as `cfg.seed` to repeat the run. The same seed makes the same inputs on
v2026.3 and v2026.4.

### Findings and crashers

A finding is one source line. Two aborts at the same line are one finding.
Its hit count tells how many runs reached it. A report holds at most 256
findings. More are counted in `rep.dropped`.

`run` saves the first input of each new finding to
`<crash_root>/<name>/<hash>`. The name comes from a 64-bit FNV-1a hash of
the input. The same input always has the same file. Commit the crasher files
and call `replay` in your test. The replay fails while a crasher still aborts.

`replay` returns the number of crasher files that aborted. Each one is a
finding in `rep`. The files that passed are `rep.runs` minus that number.

A save can fail. The finding stays in the report, its `saved` field is false
and `rep.save_failed` counts it.

## Limits that stay

A contained worker catches an abort. It cannot catch these cases. They end
the whole program:

- A hang. A loop that never ends.
- A crash in C code.
- A stack overflow or a guard-page hit.
- A call to `exit` in the target.

Goose also refuses a global variable that is not flat inside a worker. The
compiler reports this error. Pass such data in the input instead.

All abort messages of `call_law` share one site, because the abort happens
inside the package. Run one law for each `run`.

The fuzzer has no coverage guidance. It does not learn which inputs reach new
code. It mutates by bit flip, byte insert, byte delete and splice of two
seeds.

### Pattern: save the input, then restart

Write each input to a file before the run. If the program dies, the file
holds the input that killed it. On the next start, replay that file as a
crasher. Use a script that restarts the program until it ends clean.

This pattern is not tested in this package.

### Pattern: a watchdog worker

A second worker can watch the clock. When a run takes too long, it saves the
current input and calls `exit`. This ends the program, so combine it with the
restart pattern.

This pattern is not verified.

## Not verified

- Windows with a compiler other than MSVC. The CI uses the Visual Studio
  that the runner has.
- The rate on a real parser. The rate on a trivial target is 19000 runs a
  second on v2026.4. On v2026.3 it falls as aborting runs add up.
- The watchdog and the restart patterns.

## Test

```sh
TMPDIR=/some/scratch bash run-gate.sh /path/to/goose-release
```

The gate checks the entry file, then builds and runs the tests and each
example. Run it once for each compiler.

## License

MIT
