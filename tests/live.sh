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
# A call to a plugin the shell has never heard of answers "unknown" and exits 0,
# so the answer is what has to be checked, not the status. Getting this wrong
# ran the whole smoke against nothing — and its cleanup wrote menu entries for
# a plugin that wasn't installed.
loaded=$(omarchy-shell shell call yordanbuilds.rig status '' 2>/dev/null || true)
case $loaded in
  closed | open) ;;
  *) echo "skip: rig plugin not loaded"; exit 0 ;;
esac
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
  "exit": {
    "slow": "sleep 1 && echo serving",
    "dep": { "run": "echo EXIT_GATE_OPEN", "after": "slow" }
  },
  "listen": {
    "srv": "node -e \"const i=setInterval(()=>console.log('boot'),500);setTimeout(()=>{clearInterval(i);require('http').createServer().listen(8931)},4000)\"",
    "dep2": { "run": "echo LISTEN_GATE_OPEN", "after": "srv" }
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
[[ $shape == "3/5" ]] || fail "workspace shape: $shape (want 3/5)"

sleep 7
ws=$(herdr workspace list | node -e '
  let d = ""
  process.stdin.on("data", c => d += c).on("end", () => {
    console.log(JSON.parse(d).result.workspaces.find(x => x.label === process.argv[1]).workspace_id)
  })' "$STACK")
gate_open() { # <pane-label> <marker>
  local pane
  pane=$(herdr pane list --workspace "$ws" | node -e '
    let d = ""
    process.stdin.on("data", c => d += c).on("end", () => {
      console.log(JSON.parse(d).result.panes.find(p => p.label === process.argv[1]).pane_id)
    })' "$1")
  herdr pane read "$pane" --source detection --lines 30 | tr -d '\n' | grep -q "$2"
}
gate_open dep EXIT_GATE_OPEN || fail "exit gate never released"
gate_open dep2 LISTEN_GATE_OPEN || fail "listener gate never released"

omarchy-shell shell call yordanbuilds.rig kill "{\"stack\":\"$STACK\"}" >/dev/null
sleep 2
herdr workspace list | grep -qF "\"label\":\"$STACK\"" && fail "workspace survived kill"

echo "live smoke: all good"
