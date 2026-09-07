#!/usr/bin/env bash
# Runs HerdrRunner inside a headless Quickshell — its Process and stream
# parsers live in the quickshell binary, so no other engine can load them.
# The QML file under test says what it pins down. Run: bash tests/runner-smoke.sh
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

QS=""
for candidate in quickshell qs; do
  if command -v "$candidate" >/dev/null 2>&1; then QS="$candidate"; break; fi
done
if [[ -z $QS ]]; then
  echo "runner-smoke: no quickshell found — install quickshell" >&2
  exit 1
fi

# Quickshell loads QML only from the config folder — the directory of the
# file it is pointed at — so the runner and its helper are staged beside the
# test instead of imported across the tree.
stage="$(mktemp -d /tmp/rig-runner.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
cp "$HERE/HerdrRunner.qml" "$HERE/Builder.mjs" "$HERE/tests/qml/runner.qml" "$stage/"

# Quickshell also wants a runtime dir for its log and IPC socket; a bare CI
# container has none, and a unix socket path must stay short.
if [[ -z ${XDG_RUNTIME_DIR:-} ]]; then
  XDG_RUNTIME_DIR="$stage/run"
  mkdir -p "$XDG_RUNTIME_DIR"
  export XDG_RUNTIME_DIR
fi

# A runner that never caps its child hangs on the flood step; the timeout
# turns that hang into a failure instead of a stuck job.
out="$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
  timeout 60 "$QS" -p "$stage/runner.qml" 2>&1)"
status=$?
printf '%s\n' "$out" | grep -E 'qml|RUNNER|ERROR|error' | grep -v 'quickshell.ipc'
if [[ $status -eq 124 ]]; then
  echo "runner-smoke: FAIL (timed out — a step never came back)" >&2
  exit 1
fi
if [[ $out != *"RUNNER OK"* ]]; then
  echo "runner-smoke: FAIL (exit $status)" >&2
  exit 1
fi
echo "runner-smoke: ok"
