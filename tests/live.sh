#!/usr/bin/env bash
# Live smoke test against the running omarchy-shell and Herdr session.
# Builds a throwaway stack, checks the workspace shape and the readiness
# gate, kills it, and leaves everything as it found it.
# Run: bash tests/live.sh
set -euo pipefail

STACK="rigtest-live"
DIR="$HOME/.config/rig/stacks"
FILE="$DIR/$STACK.json"

herdr workspace list >/dev/null 2>&1 || { echo "skip: no running Herdr server"; exit 0; }
omarchy-shell shell call yordanbuilds.rig status '' >/dev/null 2>&1 || { echo "skip: rig plugin not loaded"; exit 0; }
[[ -e $FILE ]] && { echo "abort: $FILE already exists"; exit 1; }

fail() { echo "FAIL: $*" >&2; cleanup; exit 1; }

cleanup() {
  omarchy-shell -q shell call yordanbuilds.rig kill "{\"stack\":\"$STACK\"}" || true
  sleep 1
  rm -f "$FILE"
  "$(dirname "${BASH_SOURCE[0]}")/../bin/rig-menu-sync" || true
}
trap cleanup EXIT

mkdir -p "$DIR" /tmp/rigtest-live
cat >"$FILE" <<'EOF'
{
  "root": "/tmp/rigtest-live",
  "server": {
    "slow": "sleep 1 && echo serving",
    "dep": { "run": "echo GATE_RELEASED", "after": "slow" }
  },
  "terminal": null
}
EOF

out=$(omarchy-shell shell call yordanbuilds.rig up "{\"stack\":\"$STACK\",\"background\":true}")
[[ $out == "building $STACK" ]] || fail "up returned: $out"
sleep 3

shape=$(herdr workspace list | node -e '
  let d = ""
  process.stdin.on("data", c => d += c).on("end", () => {
    const w = JSON.parse(d).result.workspaces.find(x => x.label === process.argv[1])
    console.log(w ? w.tab_count + "/" + w.pane_count : "missing")
  })' "$STACK")
[[ $shape == "2/3" ]] || fail "workspace shape: $shape (want 2/3)"

sleep 3
ws=$(herdr workspace list | node -e '
  let d = ""
  process.stdin.on("data", c => d += c).on("end", () => {
    console.log(JSON.parse(d).result.workspaces.find(x => x.label === process.argv[1]).workspace_id)
  })' "$STACK")
pane=$(herdr pane list --workspace "$ws" | node -e '
  let d = ""
  process.stdin.on("data", c => d += c).on("end", () => {
    console.log(JSON.parse(d).result.panes.find(p => p.label === "dep").pane_id)
  })')
herdr pane read "$pane" --source recent-unwrapped --lines 30 | grep -q GATE_RELEASED || fail "readiness gate never released"

omarchy-shell shell call yordanbuilds.rig kill "{\"stack\":\"$STACK\"}" >/dev/null
sleep 2
herdr workspace list | grep -qF "\"label\":\"$STACK\"" && fail "workspace survived kill"

echo "live smoke: all good"
