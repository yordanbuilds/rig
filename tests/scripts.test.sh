#!/usr/bin/env bash
# Sandboxed tests for Rig's bash scripts. No live shell, Herdr, or Hyprland
# needed: omarchy-shell, hyprctl, herdr, and friends are PATH shims that log
# their arguments. Run: bash tests/scripts.test.sh
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0 FAIL=0

check() { # <label> <condition...>
  local label="$1"; shift
  if "$@"; then PASS=$((PASS+1)); echo "ok    $label"
  else FAIL=$((FAIL+1)); echo "FAIL  $label"; fi
}

fresh_sandbox() {
  SB="$(mktemp -d)"
  LOG="$SB/calls.log"; : >"$LOG"
  mkdir -p "$SB/bin" "$SB/.config/hypr" "$SB/.config/rig/stacks" "$SB/.config/omarchy/extensions" "$SB/.local/bin"
  touch "$SB/.config/hypr/bindings.lua"

  cat >"$SB/bin/omarchy-shell" <<SHIM
#!/usr/bin/env bash
echo "omarchy-shell \$*" >>"$LOG"
if [[ \${2:-} == call && \${4:-} == list ]]; then
  out=\$(grep -o '"out":"[^"]*"' <<<"\$5" | cut -d'"' -f4)
  [[ -n \$out ]] && printf '[]' >"\$out"
  echo listing
else
  echo ok
fi
SHIM
  cat >"$SB/bin/hyprctl" <<SHIM
#!/usr/bin/env bash
echo "hyprctl \$*" >>"$LOG"
cat "${SB}/hyprctl.out" 2>/dev/null || echo "[]"
SHIM
  cat >"$SB/bin/herdr" <<SHIM
#!/usr/bin/env bash
echo "herdr \$*" >>"$LOG"
[[ -e "${SB}/herdr.down" ]] && exit 1
case "\$*" in
  *process-info*) echo '{"result":{"process_info":{}}}' ;;
  *"pane read"*)
    [[ -e "${SB}/pane.churn" ]] && echo "line \$RANDOM" >>"${SB}/pane.out"
    cat "${SB}/pane.out" 2>/dev/null || true ;;
  *) echo '{"result":{"workspaces":[]}}' ;;
esac
SHIM
  cat >"$SB/bin/pgrep" <<SHIM
#!/usr/bin/env bash
exit 1
SHIM
  for shim in omarchy-notification-send omarchy-launch-terminal-herdr omarchy-launch-editor jq; do
    cat >"$SB/bin/$shim" <<SHIM
#!/usr/bin/env bash
echo "$shim \$*" >>"$LOG"
SHIM
  done
  cat >"$SB/bin/jq" <<SHIM
#!/usr/bin/env bash
echo "jq \$*" >>"$LOG"
cat "${SB}/jq.out" 2>/dev/null || echo 0
SHIM
  chmod +x "$SB/bin/"*
  export HOME="$SB"
  export PATH="$SB/bin:$HERE/bin:$PATH"
}

logged() { grep -qF "$1" "$LOG"; }

# --- bin/rig: argument forwarding -------------------------------------------
fresh_sandbox
rig acme >/dev/null
check "sugar forwards up with background:false" logged 'call yordanbuilds.rig up {"stack":"acme","background":false}'
rig acme -b >/dev/null
check "sugar keeps trailing -b flag" logged 'call yordanbuilds.rig up {"stack":"acme","background":true}'
rig up widgets --background >/dev/null
check "explicit up honors --background" logged 'call yordanbuilds.rig up {"stack":"widgets","background":true}'
rig kill acme >/dev/null
check "kill forwards stack name" logged 'call yordanbuilds.rig kill {"stack":"acme"}'
rig new shop --from acme >/dev/null
check "new --from forwards create with source" logged 'call yordanbuilds.rig create {"name":"shop","from":"acme"}'
rig new shop >/dev/null
check "new without --from omits source" logged 'call yordanbuilds.rig create {"name":"shop"}'
rig >/dev/null
check "bare rig toggles the menu at trigger.rig" logged 'toggle omarchy.menu {"menu":"trigger.rig"}'
out=$(rig list)
check "list round-trips the out file" test "$out" = "[]"
rig up 2>/dev/null; rc=$?
check "up without a stack exits nonzero" test "$rc" -ne 0

# --- rig-menu-sync -----------------------------------------------------------
fresh_sandbox
printf '{ "root": "/r", "t": "x" }' >"$SB/.config/rig/stacks/acme.json"
printf '{ "root": "/r", "t": "x" }' >"$SB/.config/rig/stacks/my.app.json"
MENU="$SB/.config/omarchy/extensions/omarchy-menu.jsonc"
printf '{\n  // note\n  "personal.notes": {"icon":"x","label":"Notes","action":"foo"}\n}\n' >"$MENU"
rig-menu-sync
check "sync adds a comma to the preceding entry" grep -q '"action":"foo"},' "$MENU"
check "sync writes the stack row" grep -q '"trigger.rig.stack-acme"' "$MENU"
check "sync slugifies dotted names in ids" grep -q '"trigger.rig.stack-my-app"' "$MENU"
check "sync keeps dotted names in labels" grep -q '"label": "my.app"' "$MENU"
check "sync writes the New row" grep -q '"trigger.rig.new"' "$MENU"
rig-menu-sync
check "sync is idempotent" test "$(grep -c 'trigger.rig.stack-acme' "$MENU")" = 1
rm "$SB/.config/rig/stacks/acme.json"
rig-menu-sync
check "sync drops rows for deleted stacks" bash -c "! grep -q 'stack-acme' '$MENU'"
rm "$MENU"
rig-menu-sync
check "sync creates a missing menu file" grep -q '"trigger.rig"' "$MENU"

# --- rig-setup ---------------------------------------------------------------
fresh_sandbox
echo 0 >"$SB/jq.out"
rig-setup
BINDINGS="$SB/.config/hypr/bindings.lua"
check "setup writes the marked bind block" grep -q '>>> rig >>>' "$BINDINGS"
check "setup binds SUPER+R to the menu" grep -q 'SUPER + R' "$BINDINGS"
check "setup links the CLI" test -L "$SB/.local/bin/rig"
check "setup drops the run-once flag" test -e "$SB/.config/rig/.setup-done"
rig-setup
check "setup is a no-op on second run" test "$(grep -c '>>> rig >>>' "$BINDINGS")" = 1
sed -i '/>>> rig >>>/,/<<< rig <<</d' "$BINDINGS"
rig-setup
check "setup respects a user-deleted bind block" bash -c "! grep -q '>>> rig >>>' '$BINDINGS'"

fresh_sandbox
echo 1 >"$SB/jq.out"
rig-setup
check "setup skips the bind when SUPER+R is taken" bash -c "! grep -q '>>> rig >>>' '$SB/.config/hypr/bindings.lua'"
check "setup notifies about the taken key" logged 'omarchy-notification-send Rig is ready SUPER+R was taken'

# --- rig-ensure-herdr --------------------------------------------------------
fresh_sandbox
rig-ensure-herdr
check "ensure launches a terminal when no client exists" logged 'omarchy-launch-terminal-herdr'
fresh_sandbox
touch "$SB/herdr.down"
rig-ensure-herdr 2>/dev/null; rc=$?
check "ensure fails honestly when the server never answers" test "$rc" -ne 0

# --- rig uninstall (file cleanup only; plugin removal is shimmed) ------------
fresh_sandbox
cat >"$SB/bin/omarchy" <<SHIM
#!/usr/bin/env bash
echo "omarchy \$*" >>"$LOG"
SHIM
chmod +x "$SB/bin/omarchy"
printf -- '-- mine\n-- >>> rig >>>\nbind\n-- <<< rig <<<\n' >"$SB/.config/hypr/bindings.lua"
printf '{\n  "trigger.rig": {},\n}\n' >"$SB/.config/omarchy/extensions/omarchy-menu.jsonc"
ln -s /dev/null "$SB/.local/bin/rig"
touch "$SB/.config/rig/.setup-done"
printf '{ "root": "/r", "t": "x" }' >"$SB/.config/rig/stacks/keepme.json"
printf 'y\nn\n' | rig uninstall >/dev/null 2>&1
check "uninstall strips the bind block" bash -c "! grep -q 'rig >>>' '$SB/.config/hypr/bindings.lua'"
check "uninstall keeps stacks when declined" test -e "$SB/.config/rig/stacks/keepme.json"
check "uninstall keeps the user's own bindings" grep -q -- '-- mine' "$SB/.config/hypr/bindings.lua"
check "uninstall strips menu entries" bash -c "! grep -q 'trigger.rig' '$SB/.config/omarchy/extensions/omarchy-menu.jsonc'"
check "uninstall removes the CLI symlink" bash -c "! test -e '$SB/.local/bin/rig'"
check "uninstall removes the plugin" logged 'omarchy plugin remove yordanbuilds.rig --yes'

fresh_sandbox
cat >"$SB/bin/omarchy" <<SHIM
#!/usr/bin/env bash
echo "omarchy \$*" >>"$LOG"
SHIM
chmod +x "$SB/bin/omarchy"
printf '{ "root": "/r", "t": "x" }' >"$SB/.config/rig/stacks/goner.json"
printf 'y\ny\n' | rig uninstall >/dev/null 2>&1
check "uninstall deletes stacks when confirmed" bash -c "! test -e '$SB/.config/rig'"

# --- rig-wait-ready ----------------------------------------------------------
fresh_sandbox
printf 'typed command\nRIG_READY\n' >"$SB/pane.out"
out=$(RIG_WAIT_TIMEOUT_MS=3000 rig-wait-ready w1:p1 RIG_READY)
check "wait-ready releases on the pattern" test -z "$out"
fresh_sandbox
printf 'banner\nlistening\n' >"$SB/pane.out"
out=$(RIG_WAIT_TIMEOUT_MS=6000 RIG_WAIT_MIN_MS=400 RIG_WAIT_SETTLE_MS=400 rig-wait-ready w1:p1 RIG_READY)
check "wait-ready settles on quiet output" test -z "$out"
fresh_sandbox
printf 'start\n' >"$SB/pane.out"
touch "$SB/pane.churn"
out=$(RIG_WAIT_TIMEOUT_MS=1200 rig-wait-ready w1:p1 RIG_READY)
check "wait-ready gives up on churning output" grep -q "gave up" <<<"$out"

echo
echo "passed $PASS, failed $FAIL"
exit $((FAIL > 0))
