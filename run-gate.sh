#!/usr/bin/env bash
# The gate for goose-fuzz, for one Goose release.
#
#   TMPDIR=/some/dir bash run-gate.sh /path/to/goose-vX.Y.Z
#
# It checks the entry file, builds and runs the tests, then builds and runs
# each example. A worker is a thread, so every program builds with
# "goose build" and then runs as a file. "goose run" cannot run threads.
#
# The gate also builds the coverage test twice. The plain build must print
# the word "off". The build with the cov-cc wrapper must print "live". The
# coverage step is skipped on Windows, because MSVC has no coverage flag.
set -uo pipefail

compiler_dir="${1:-}"
# Windows ships goose.exe.
goose="$compiler_dir/goose"
[[ -x "$goose" ]] || goose="$compiler_dir/goose.exe"
if [[ -z "$compiler_dir" || ! -x "$goose" ]]; then
    echo "usage: TMPDIR=dir bash run-gate.sh <goose-release-dir>" >&2
    exit 2
fi
if [[ -z "${TMPDIR:-}" || ! -d "$TMPDIR" ]]; then
    echo "run-gate.sh: set TMPDIR to an existing scratch directory" >&2
    exit 2
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d "$TMPDIR/fuzz-gate.XXXXXX")"
trap 'rm -rf "$work"' EXIT
cd "$here"

step() {
    local name="$1"
    shift
    if "$@" > "$work/log" 2>&1; then
        echo "ok $name"
    else
        echo "FAIL $name"
        tail -n 30 "$work/log"
        exit 1
    fi
}

echo "compiler: $("$goose" version 2>&1 | head -n 1)"
step "check fuzz.goose" "$goose" check fuzz.goose
step "build test/run.goose" "$goose" build --debug test/run.goose -o "$work/test-run"
step "run test/run.goose" bash -c "cd '$here' && '$work/test-run'"

shopt -s nullglob
for example in examples/*.goose; do
    name="$(basename "$example" .goose)"
    step "build $example" "$goose" build --debug "$example" -o "$work/ex-$name"
    step "run $example" bash -c "cd '$here' && '$work/ex-$name'"
done
# The plain build of the coverage test. Without the wrapper the program has
# no coverage, and the test checks that the run then behaves as a plain run.
step "build test/cov.goose plain" "$goose" build --debug test/cov.goose -o "$work/cov-off"
step "run test/cov.goose plain" bash -c \
    "cd '$here' && '$work/cov-off' > '$work/cov-off-out' && grep -qx off '$work/cov-off-out'"

# The coverage build. MSVC has no coverage flag, so Windows skips this step.
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        echo "skip coverage build: no coverage flag on Windows"
        ;;
    *)
        step "build test/cov.goose with cov-cc" env GOOSE_CC="$here/cov-cc" \
            "$goose" build --debug test/cov.goose -o "$work/cov-live"
        step "run test/cov.goose with cov-cc" bash -c \
            "cd '$here' && '$work/cov-live' > '$work/cov-out' && grep -qx live '$work/cov-out'"
        ;;
esac
echo "gate passed"
