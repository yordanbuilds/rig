import Quickshell
import Quickshell.Io
import QtQuick
import "Builder.js" as Builder

// Rig's headless core. The stack list lives in the Omarchy menu (entries
// managed by bin/rig-menu-sync), so this item draws nothing: it hosts the
// build engine, the IPC methods the CLI calls, and first-load setup.
// Summoning the plugin forwards to the menu at trigger.rig.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string pluginId: (manifest && manifest.id) || "yordanbuilds.rig"
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/yordanbuilds.rig"
  property string stacksDir: Quickshell.env("HOME") + "/.config/rig/stacks"
  property string homeDir: Quickshell.env("HOME")

  function open(payloadJson) {
    if (root.shell && typeof root.shell.summon === "function")
      root.shell.summon("omarchy.menu", JSON.stringify({ menu: "trigger.rig" }))
  }

  function close() { }

  function toggle() { root.open("{}") }

  function status() { return "closed" }

  function notify(title, body) {
    Quickshell.execDetached(["omarchy-notification-send", title, body])
  }

  function menuSync() {
    Quickshell.execDetached([root.pluginDir + "/bin/rig-menu-sync"])
  }

  HerdrRunner { id: runner }
  HerdrRunner { id: prepRunner }

  // First-load omakase setup (CLI symlink, keybinding, menu block), then a
  // menu sync so manually dropped stack files appear after a shell restart.
  Process {
    id: setupProcess
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/yordanbuilds.rig/bin/rig-setup"]
    onExited: root.menuSync()
  }
  Component.onCompleted: setupProcess.running = true

  function herdrError(msg) {
    return /connect|refused|socket|not.?running|no herdr/i.test(msg) ? "no running Herdr server — start herdr first" : msg
  }

  function report(out, ok, body) {
    if (out) {
      prepRunner.run([{ label: "write result", argv: ["bash", "-c", 'printf "%s" "$1" > "$2"', "rig-out",
        (ok ? "ok" : "err") + "\n" + body, out] }], {}, function() {}, function() {})
    } else if (!ok) {
      root.notify("Rig", body)
    }
  }

  function up(argJson) {
    var arg
    try { arg = JSON.parse(argJson || "{}") } catch (e) { return "error: bad argument JSON" }
    var name = arg.stack
    if (!name || !Builder.NAME_RE.test(name)) return "error: invalid stack name"
    var background = arg.background === true
    var out = arg.out || null
    var path = root.stacksDir + "/" + name + ".json"
    var prep = [
      { label: "read " + name + ".json", argv: ["cat", path], collect: "raw" },
      { label: "list workspaces", argv: ["herdr", "workspace", "list"], collect: "wsjson" }
    ]
    if (!background) prep.unshift({ label: "open Herdr", argv: [root.pluginDir + "/bin/rig-ensure-herdr"] })
    prepRunner.run(prep, {}, function(ctx) {
      var stack, errors, workspaces
      try {
        stack = Builder.normalize(JSON.parse(ctx.raw), root.homeDir)
        errors = Builder.validate(stack)
        workspaces = Builder.parseWorkspaces(ctx.wsjson)
      } catch (e) { root.report(out, false, name + ": " + String(e.message || e)); return }
      if (errors.length) { root.report(out, false, name + " is invalid — " + errors[0]); return }
      var existing = workspaces.byLabel[name]
      if (existing) {
        if (!background) runner.run([{ label: "focus workspace", argv: ["herdr", "workspace", "focus", existing.id] }],
          {}, function() { root.report(out, true, name + " is already up — took you there") },
          function(msg) { root.report(out, false, name + ": " + root.herdrError(msg)) })
        else root.report(out, true, name + " is already up")
        return
      }
      root.executePlan(name, stack, background, workspaces.focusedActiveTabId, out)
    }, function(msg) {
      if (msg.indexOf("read ") === 0) root.report(out, false, "no stack named \"" + name + "\" in " + root.stacksDir)
      else root.report(out, false, name + ": " + root.herdrError(msg))
    })
    return "building " + name
  }

  function executePlan(name, stack, background, previousTabId, out) {
    var planObj = Builder.plan(name, stack, String(Date.now()))
    var steps = planObj.steps.slice()
    if (!background) steps = steps.concat(Builder.focusSteps(planObj))
    runner.run(steps, {}, function(ctx) {
      if (background && previousTabId) {
        // Bounce: make the stack's last tab its active tab, then restore the user's view.
        runner.run([
          { label: "activate last tab", argv: ["herdr", "tab", "focus", ctx[planObj.lastTabKey]] },
          { label: "restore focus", argv: ["herdr", "tab", "focus", previousTabId] }
        ], {}, function() {}, function(msg) { root.notify("Rig: " + name, root.herdrError(msg)) })
      }
      root.report(out, true, name + " is up")
    }, function(msg) {
      root.report(out, false, name + " build failed — " + root.herdrError(msg))
    })
  }

  function killStack(argJson) {
    var arg
    try { arg = JSON.parse(argJson || "{}") } catch (e) { return "error: bad argument JSON" }
    var name = arg.stack
    if (!name) return "error: missing stack name"
    var out = arg.out || null
    prepRunner.run([{ label: "list workspaces", argv: ["herdr", "workspace", "list"], collect: "wsjson" }],
      {}, function(ctx) {
        var existing
        try { existing = Builder.parseWorkspaces(ctx.wsjson).byLabel[name] } catch (e) { root.report(out, false, String(e)); return }
        if (!existing) { root.report(out, false, "\"" + name + "\" is not running"); return }
        runner.run([{ label: "close workspace", argv: ["herdr", "workspace", "close", existing.id] }],
          {}, function() { root.report(out, true, name + " closed") },
          function(msg) { root.report(out, false, name + ": " + root.herdrError(msg)) })
      }, function(msg) { root.report(out, false, root.herdrError(msg)) })
    return "killing " + name
  }

  function kill(argJson) { return killStack(argJson) }

  function list(argJson) {
    var arg
    try { arg = JSON.parse(argJson || "{}") } catch (e) { return "error: bad argument JSON" }
    var out = arg.out
    if (!out || out.indexOf("/") !== 0) return "error: list needs an absolute \"out\" path"
    prepRunner.run([
      { label: "list stacks", argv: ["bash", "-c",
        'for f in "$HOME"/.config/rig/stacks/*.json; do [ -e "$f" ] || continue; printf "%s\\t%s\\n" "$(basename "$f" .json)" "$(base64 -w0 "$f")"; done'],
        collect: "listing" },
      { label: "list workspaces", argv: ["herdr", "workspace", "list"], collect: "wsjson" }
    ], {}, function(ctx) {
      var workspaces = { byLabel: {} }
      try { workspaces = Builder.parseWorkspaces(ctx.wsjson) } catch (e) { }
      var result = Builder.parseStacksListing(ctx.listing || "", Qt.atob).map(function(entry) {
        var ws = workspaces.byLabel[entry.name]
        return { name: entry.name, running: !!ws, workspace_id: ws ? ws.id : null }
      })
      result.sort(function(a, b) { return a.name < b.name ? -1 : 1 })
      var body
      if (arg.format === "json") body = JSON.stringify(result)
      else if (result.length === 0) body = "no stacks yet — rig new <name>"
      else body = result.map(function(r) {
        return r.running ? "\x1b[1;32m●\x1b[0m " + r.name : "\x1b[2m○\x1b[0m " + r.name
      }).join("\n")
      prepRunner.run([{ label: "write listing", argv: ["bash", "-c", 'printf "%s" "$1" > "$2"', "rig-list", body, out] }],
        {}, function() {}, function(msg) { root.notify("Rig", root.herdrError(msg)) })
    }, function(msg) {
      prepRunner.run([{ label: "write listing", argv: ["bash", "-c", 'printf "%s" "$1" > "$2"', "rig-list",
        JSON.stringify({ error: root.herdrError(msg) }), out] }], {}, function() {}, function() {})
    })
    return "listing"
  }

  function create(argJson) {
    var arg
    try { arg = JSON.parse(argJson || "{}") } catch (e) { return "error: bad argument JSON" }
    var name = arg.name
    if (!name || !Builder.NAME_RE.test(name)) return "error: stack names must match A-Za-z0-9._-"
    var from = arg.from || null
    if (from !== null && !Builder.NAME_RE.test(from)) return "error: stack names must match A-Za-z0-9._-"
    var target = root.stacksDir + "/" + name + ".json"
    var source = from ? root.stacksDir + "/" + from + ".json" : root.pluginDir + "/template.json"
    prepRunner.run([
      { label: "create stack file", argv: ["bash", "-c",
        'set -e; mkdir -p "$(dirname "$1")"; [ ! -e "$1" ] || { echo "exists" >&2; exit 3; }; cp "$2" "$1"', "rig-new",
        target, source] }
    ], {}, function() {
      root.menuSync()
      Quickshell.execDetached(["omarchy-launch-editor", target])
    }, function(msg) {
      if (msg.indexOf("exists") !== -1) root.notify("Rig", "\"" + name + "\" already exists — not overwriting")
      else root.notify("Rig", msg)
    })
    return "created " + name
  }
}
