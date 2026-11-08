# goose-fuzz

[![ci](https://github.com/rekanalar/goose-fuzz/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-fuzz/actions/workflows/ci.yml)

Fuzzing for Goose programs: seeded mutation, crash isolation, replay and
shrinking. It works with Goose v2026.3 and v2026.4.

The package runs your function on many mutated byte inputs. Each run happens
in a contained worker. An abort ends only that run. The abort becomes a
finding with its message and its source line, and the run goes on.

## Install

Add this to the root file of the program that uses it:

```goose
import fuzz from "rekanalar/goose-fuzz@v1.0.0";
```

The child mode needs one more package in the same root file:

```goose
import process from "rekanalar/goose-process@v1.0.0";
```

The CI runs the gate on Linux, macOS and Windows. It uses Goose v2026.3 and
v2026.4 on each.

## Use

Write a function that takes a byte slice. Write one `thread_fn` line that
hands it to the package. Call `fuzz::run`.

```goose
import std;
import fuzz from "rekanalar/goose-fuzz@v1.0.0";

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
| `fuzz::call_typed(F)` | As `call`, for a typed target. `F` takes the `Reader` over the input. |
| `fuzz::dict_add(cfg, token)` | Append one token to `cfg.dict` as an escaped line. False when the buffer is full or the token is empty. |
| `fuzz::dict_load(cfg, path, err)` | Read a dictionary file in the libFuzzer format and append its text to `cfg.dict`. False on a bad line, with `line N:` in `err`. |
| `fuzz::dict_parse(text, dpool, dends, err)` | Parse dictionary text into a token pool. Returns the count, or -1 with `line N:` in `err`. |
| `fuzz::reader(data)` | Build a `Reader` over the bytes. |
| `fuzz::read_bool(r)` | One byte as a `bool`. |
| `fuzz::read_i64(r, lo, hi)` | Eight bytes into `[lo, hi]`. Refuses `lo > hi` with 0. |
| `fuzz::read_string(r, max_len)` | Up to `max_len` bytes. |
| `fuzz::read_i64_list(r, max_items)` | One count byte, then 8 bytes per item. |
| `fuzz::cores()` | One worker for each core, probed from the system. |
| `fuzz::derive_seed(seed, batch, worker)` | The seed of one batch of one worker. |
| `fuzz::config()` | A `Config` with the defaults. |
| `fuzz::run(name, cfg, rep, W)` | Fuzz the worker `W`. Fills `rep`. Returns the finding count, or -1 when the seed directory cannot be read. |
| `fuzz::replay(name, crash_root, rep, W)` | Run every saved crasher once. Returns the number that aborted. Passed files: `rep.runs` minus that. |
| `fuzz::run_one(input, why, W)` | Run one input. Returns false and fills `why` when it aborts. |
| `fuzz::is_child()` | True when the program was started as a child of the parent mode. |
| `fuzz::child_batch(W)` | The child side. Runs one batch, saves each input before the run. Exit code: 0 clean, 126 error. |
| `fuzz::run_isolated(name, cfg, rep)` | The parent side. Runs the child in batches. A hang, a crash in C code, a stack overflow or a call to `exit` becomes a finding. |
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
| `child` | empty | The program name of the child binary. Empty refuses the child mode. |
| `workers` | 0 | The child workers that run at once. 0 picks one for each core, capped at 8. The valid range is 1 to 15. |
| `token_rate` | 25 | The percent of mutations that use a token. |
| `dict` | empty | The dictionary text, in the libFuzzer format. It holds at most 4096 bytes. |

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

## A dictionary

A parser fuzzer needs the words of the protocol. Blind byte flips rarely
build `<?xml` or `GET `. The mutator inserts a token, or writes it over
input bytes, at `cfg.token_rate` percent. All choices come from the
seeded generator, so a seed repeats a run. With no tokens the mutator
makes the same inputs as v0.2.0.

The text sits in `cfg.dict`, in the libFuzzer format:

```
# the words of the protocol
word1="GET "
word2="<?xml"
name="\x00\xff"
```

A line is `"value"` or `name="value"`. A line that starts with `#` is a
comment. A blank line is ignored. The escapes are `\\`, `\"` and
`\xNN`. Duplicate tokens stay. Load a file with `dict_load`, or append
one token with `dict_add`:

```goose
var cfg = fuzz::config();
var err: u8[>..] = [];
if !fuzz::dict_load(cfg, "words.dict", err) {
    print(err);
    exit(1);
}
fuzz::dict_add(cfg, "GOOSE");
```

A bad line fails the load and names the line. The dictionary text holds
at most 4096 bytes. See `examples/dict.goose`.

## Typed values

A target that wants values, not bytes, reads them from a `Reader` over
the mutated bytes:

```goose
fn logic(r: fuzz::Reader&) {
    let n = fuzz::read_i64(r, 1000, 1010);
    let flag = fuzz::read_bool(r);
    let name = fuzz::read_string(r, 16);
    let xs = fuzz::read_i64_list(r, 8);
    if n > 1005 && flag { abort("typed"); }
}

thread_fn typed_target() { fuzz::call_typed(logic); }
```

Pass `typed_target` to `run`, `replay` or `shrink` as any worker. No read
fails. A read past the end gives the default of its type: false, 0, the
empty string or the empty list. A range with the low bound above the high
bound is refused with 0.

The same bytes give the same values in every run. The crasher stays the
byte input, so replay and shrink work unchanged. See
`examples/typed.goose`.

## The child mode

The four cases at the end of the limits list end the whole program. The
child mode turns them into findings. The parent runs the fuzzer again as a
child process, in batches. The child saves every input to a file before it
runs it. When the child dies or hangs, the parent reads that file, records
a finding and starts the next child.

```goose
fn main() {
    if fuzz::is_child() {
        exit(fuzz::child_batch(target));
    }
    var cfg = fuzz::config();
    cfg.child.append(args()[0]);
    cfg.runs = 50000;
    var rep = fuzz::Report { };
    let found = fuzz::run_isolated("parse", cfg, rep);
    /* the report and the crashers, as with run */
}
```

The parent gives every child a limit of 10 seconds, so a hung child can
never block the run. The name travels to the child as the last argument,
so one binary can serve several targets.

The parent writes its files in a private directory under `TMPDIR`. The
name holds the seed and the clock, so two runs never share a file.

With `cfg.workers` above 1 the parent starts that many children at once.
The default of 0 picks one worker for each core, capped at 8. Each worker
and each batch gets its own seed, derived from the seed of the run. No
two batches repeat inputs.

The parent merges the findings of all workers: one finding for each
site, with the hits added up. A worker count above 15 is refused before
any child starts. The handle table of the process package holds 16
slots.

## Security

The package runs the program that a caller names and writes the findings
into a directory. These protections go beyond the reference libraries.

- The child mode stops a child that hangs at the time limit of the
  configuration. The input becomes a finding, so a hang in the target ends
  one child and not the whole run.
- The number of workers is capped at 15, so a machine with many cores
  starts no more children than that.
- No input is longer than `max_len`, and the dictionary holds at most 4096
  bytes. A seed file or a dictionary from an untrusted source cannot make
  the package hold a long text.

These risks stay.

- The child mode starts the program that the caller names. A caller must
  name a program that it trusts.
- The package writes the crashing inputs into the crasher root of the
  caller. An input may hold a secret of the program under test.
- The dictionary file is read as text. A bad line is refused with the line
  number, and no line of it runs as code.

## Limits that stay

A contained worker catches an abort. It cannot catch these cases. They end
the whole program:

- A hang. A loop that never ends.
- A crash in C code.
- A stack overflow or a guard-page hit.
- A call to `exit` in the target.

The child mode catches all four. Its findings carry synthetic sites:
`child:exit N` or `child:stopped`, because the child cannot report its
abort line across its own death. The input is still exact, and the replay
still runs it. A crasher whose target kills the process has no replay in
one process; run it through the child mode instead.

The child reports an error with the code 126. A target that calls
`exit(126)` collides with it. The parent then reports a hard error and
starts no child again.

Goose also refuses a global variable that is not flat inside a worker. The
compiler reports this error. Pass such data in the input instead.

All abort messages of `call_law` share one site, because the abort happens
inside the package. Run one law for each `run`.

The child takes two optional arguments after the name: the dictionary file
path and the token rate. A parent that passes only seven arguments keeps
working with no dictionary.

The fuzzer has no coverage guidance. It does not learn which inputs reach new
code. It mutates by bit flip, byte insert, byte delete and splice of two
seeds. With a dictionary it inserts or overwrites with a token.

The compiler gives no way to build coverage guidance. It would need
`-fsanitize-coverage` and a map back to Goose lines through `#line`
directives in the generated C. v2026.4 has neither.

The child mode does the save-and-restart pattern of the older releases
in the package itself. The watchdog pattern is no longer needed there: the
parent stops a hung child at its limit.

## Not verified

- Windows with a compiler other than MSVC. The CI uses the Visual Studio
  that the runner has.
- The rate on a real parser. The rate on a trivial target is 19000 runs a
  second on v2026.4. On v2026.3 it falls as aborting runs add up.
- The watchdog and the restart patterns.
- The child mode on Windows. The CI runs the suite there, including the
  child cases, but no machine of this project runs Windows.
- The rate of the child mode on macOS and Windows. The Linux rate is
  10000 inputs a second on a trivial target.

## Test

```sh
TMPDIR=/some/scratch bash run-gate.sh /path/to/goose-release
```

The gate checks the entry file, then builds and runs the tests and each
example. Run it once for each compiler.

## License

MIT
