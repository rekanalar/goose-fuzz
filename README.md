# goose-fuzz

[![ci](https://github.com/rekanalar/goose-fuzz/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-fuzz/actions/workflows/ci.yml)

Fuzzing for Goose programs: seeded mutation, coverage guidance, crash
isolation, replay and shrinking. It works with Goose v2026.3 and v2026.4.

The package runs your function on many mutated byte inputs. Each run happens
in a contained worker. An abort ends only that run. The abort becomes a
finding with its message and its source line, and the run goes on.

## Install

Add this to the root file of the program that uses it:

```goose
import fuzz from "rekanalar/goose-fuzz@v1.2.0";
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
import fuzz from "rekanalar/goose-fuzz@v1.2.0";

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

## The C part

The package holds one C file, `src/cov.c`. It records the code that a run
reached. It needs no library and no system call beyond the C runtime. The
Goose compiler builds it with the C compiler of the machine.

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
| `fuzz::cov_live()` | True when the program was built with the coverage compiler. |
| `fuzz::coverage_path(out)` | Write the path of the `cov-cc` script of the installed package into `out`. False when the path has an unexpected form. |
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
| `fuzz::shrink_full(input, out, stopped, W)` | As `shrink`. `stopped` holds 1 when the budget of 20000 steps ended the work. The passes remove blocks, zero whole values, then remove single bytes. |
| `fuzz::run_with(name, cfg, rep, W, M)` | As `run`, with a mutator `M(data, out) -> bool` of the caller. `M` writes an input into `out` and returns true, or returns false to use a kind of the package. |
| `fuzz::score(v)` | Called by the target. Reports a score for the input that runs. Used when `cfg.score_mode` is 1. |
| `fuzz::last_score()` | The last score that the target reported. |
| `fuzz::best_input(rep)` | The input with the best score of the run. Empty without a score mode. |
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
| `corpus_root` | empty | The corpus root. Empty means `fuzz/corpus`. |
| `child` | empty | The program name of the child binary. Empty refuses the child mode. |
| `workers` | 0 | The child workers that run at once. 0 picks one for each core, capped at 8. The valid range is 1 to 15. |
| `token_rate` | 25 | The percent of mutations that use a token. |
| `dict` | empty | The dictionary text, in the libFuzzer format. It holds at most 4096 bytes. |
| `seed_energy` | 100 | The mutations that a seed gets before the run prefers another seed. A mutation that reaches no new class spends one. 0 turns the spending off. |
| `pool_order` | 0 | 0 mutates the oldest seed that has energy. 1 mutates the seed with the most hits. |
| `probe_ms` | 30000 | The time that the parent gives a stopped input in a second child. 0 turns the probe off. |
| `mutator_rate` | 10 | The percent of mutations that call the mutator of `run_with`. |
| `score_mode` | 0 | 1 steers by the score of the target. 2 steers by the time of the run. The run then mutates the best input half of the time. |

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

## The verdict of a gate

A gate needs one line and one exit code. The `examples/verdict.goose` program shows the pattern. It runs a target and prints the verdict. It exits with code 1 when the run found something.

```
goose build --debug examples/verdict.goose -o verdict && ./verdict
verdict: PASS, 2000 run(s), 0 finding(s)
```

A test suite needs the same result as a test result. The goose-testkit package holds the helper that records it. The number of findings, the number of runs and the text of the report go to it.

```goose
testkit::fuzz_result(t, found, rep.runs, report);
```

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

## Coverage guidance

The fuzzer can learn which inputs reach new code. Build the program with
the coverage compiler of the package. An input that reaches code that no
earlier input reached is *interesting*. The run keeps it as a seed for
later mutations, as libFuzzer and Go do. The run also saves it in the
corpus directory, so the next run starts from it.

Ask the package for the path of its compiler script. Then build with it:

```goose
var path: u8[>..] = [];
if fuzz::coverage_path(path) {
    print(path);
}
```

```sh
GOOSE_CC=/path/printed/above goose build --debug your_fuzzer.goose -o your_fuzzer
./your_fuzzer
```

The script `cov-cc` calls the C compiler of the machine with
`-fsanitize-coverage=trace-pc`. This is the step that libFuzzer asks of
its caller: pass the sanitizer flag. The script uses the first of `clang`,
`gcc` and `cc` that it finds. Set `GOOSE_COVER_CC` to name another one.

A coverage run adds two lines to the report:

```
edges: 513
interesting: 9
```

`edges` counts the distinct pieces of code that the run reached. A
program built without the script has no coverage. Its report has neither
line, and the run behaves as it did before.

The corpus lives in `<corpus_root>/<name>`. An empty root means
`fuzz/corpus`. A file holds one input, and its name is the hash of the
input. A run reads the files of that directory as seeds at its start. The
corpus holds at most 4096 files. The report counts the inputs that the
cap turned away in `corpus_dropped`.

The flag makes the target run about six times slower. The measure is a
tight loop on gcc 15.2 on Linux. Build the plain program for a run that
needs speed.

`test/cov.goose` pins the claim. A target opens three stages, one byte
for each. With the seed 1 and 20000 runs, the guided run finds the abort.

Guidance helps and does not guarantee. A target that needs five exact
bytes can stall a run. The measure of this package used three exact
bytes. A blind run found the abort on none of eight seeds. The guided
run found it on seven.

## Hit-count classes and mutations

The coverage sorts the count of an edge into eight classes. They are
1, 2, 3, 4-7, 8-15, 16-31, 32-127 and 128 or more. An input is interesting when
an edge rises above the class of every earlier input. A loop that runs
more often is then new.

Only the thread of the target records edges. The wait loop of the main
thread would otherwise add counts that change with the speed of the
machine.

`rep.class_edges[c]` holds the edges whose best class is `c`. Index 0
holds the edges that no input of the run reached. AFL++ uses a finer
table of powers of two. This package uses the eight classes of
libFuzzer.

The mutator has 20 kinds, and `rep.kind_count` counts each one.

- Bit flip, byte insert, byte delete, tail splice and two token kinds.
- Byte invert, interesting value, add or take one, and add or take an
  interesting value.
- Swap, block insert, block delete, byte overwrite and block overwrite.
- Block copy, block copy to the end and shuffle.
- A change of a number in the text, and of a binary number.
 The package wrote each kind from its description. It
holds no code of AFL++ or libFuzzer.

A seed spends one energy for each mutation that finds nothing new. The
run prefers the seeds that have energy. A seed at zero stays in the pool.
When no seed has energy, every seed gets its energy again.
`rep.seeds_retired` counts the seeds that reached zero.

## A mutator and a score

`fuzz::run_with` takes a mutator of the caller as a second function
value. The target can call `fuzz::score(v)` to say how close an input is
to a goal. With `cfg.score_mode = 1` the run mutates the best input half
of the time. `examples/score.goose` shows both.

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
never block the run. The name travels to the child as the seventh
argument after the marker, so one binary can serve several targets.

When a child stops at the limit, the parent runs the saved input again
in one new child, within `cfg.probe_ms`. A probe that ends clean with no
abort makes the finding `child:slow`: the input was slow and not a hang.
`rep.slow` counts these. A probe that stops again keeps `child:stopped`.

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

- The budget of the shrink is 20000 steps. A hostile target cannot keep
  the shrink alive without end.
- The probe has its own time limit, `probe_ms`. A hang in the probe ends
  it, and the finding keeps its site.
- The child mode stops a child that hangs at the limit of 10 seconds.
  The input becomes a finding, so a hang in the target ends one child and
  not the whole run.
- The number of workers is capped at 15, so a machine with many cores
  starts no more children than that.
- The corpus holds at most 4096 files. A target that keeps reaching new
  code cannot fill the disk of the caller.
- No input is longer than `max_len`, and the dictionary holds at most 4096
  bytes. A seed file or a dictionary from an untrusted source cannot make
  the package hold a long text.

These risks stay.

- The child mode starts the program that the caller names. A caller must
  name a program that it trusts.
- The package writes the crashing inputs into the crasher root of the
  caller. An input may hold a secret of the program under test.
- The corpus files hold inputs of the program under test, as the
  crasher files do. An input may hold a secret of that program.
- The `cov-cc` script runs the compiler that `GOOSE_COVER_CC` names. A
  caller must name a compiler that it trusts.
- The probe reruns an input that the child saved. The parent writes it to
  a file in its private directory and deletes the file after the probe. An
  input that holds a secret sits on disk for that time.
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

The child takes three optional arguments after the name: the dictionary
file path, the token rate and a status file. The probe uses the status
file to learn the count of aborts. A parent that passes only seven
arguments keeps working with no dictionary.

The child mode has no user mutator and no score. Both need the process of
the parent, and a child is a fresh process. The score travels in a queue
of the process. A child sets no value for the parent.

The coverage tells how much code a run reached. It names no source line.
The generated C of the compiler holds no `#line` directive, so a program
counter has no Goose line. The coverage part of the report gives counts
only. A finding still names its own line. The abort message carries the
file and the line of the abort, and the report gives that pair.

The child mode has no coverage guidance. Each child is a fresh process,
and its record of the code dies with it. The report of the parent names
no edges.

MSVC has no coverage flag. A program built with MSVC behaves as a
program without the script. The gate skips the coverage step on Windows.

The record of the code holds 65536 addresses. A program with more
reaches the limit, and the extra addresses go unseen. The report then
adds a line `edges lost: N`. Guidance still works on the addresses that
fit, but it cannot see new code behind the lost ones.

The coverage marks an input interesting when it reaches code that no
earlier input reached. It is also interesting when an edge rises to a
higher class of hits. The coverage flag is `trace-pc`, which gives no record of compared values.

A run reads `fuzz/corpus/<name>` at its start when that directory exists,
or the directory of `corpus_root`. The files there change the inputs of
the run. To keep the old inputs, point `corpus_root` at an empty directory.

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
