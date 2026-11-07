#!/usr/bin/env bash
# The gate for goose-fuzz, for one Goose release.
#
#   TMPDIR=/some/dir bash run-gate.sh /path/to/goose-vX.Y.Z
#
# It checks the entry file, builds and runs the tests, then builds and runs
# each example. A worker is a thread, so every program builds with
# "goose build" and then runs as a file. "goose run" cannot run threads.
set -uo pipefail

compiler_dir="${1:-}"
if [[ -z "$compiler_dir" || ! -x "$compiler_dir/goose" ]]; then
    echo "usage: TMPDIR=dir bash run-gate.sh <goose-release-dir>" >&2
    exit 2
fi
if [[ -z "${TMPDIR:-}" || ! -d "$TMPDIR" ]]; then
    echo "run-gate.sh: set TMPDIR to an existing scratch directory" >&2
    exit 2
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
goose="$compiler_dir/goose"
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
echo "gate passed"
