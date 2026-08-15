import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Builder.js" as Builder

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string pluginId: (manifest && manifest.id) || "yordanbuilds.rig"

  function open(payloadJson) {
    root.opened = true
    root.uiState = "list"
    root.selectedIndex = 0
    root.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function status() {
    return root.opened ? "open" : "closed"
  }

  function notify(title, body) {
    Quickshell.execDetached(["omarchy-notification-send", title, body])
  }

  property string stacksDir: Quickshell.env("HOME") + "/.config/rig/stacks"
  property string homeDir: Quickshell.env("HOME")

  HerdrRunner { id: runner }
  HerdrRunner { id: prepRunner }

  function up(argJson) {
    var arg
    try { arg = JSON.parse(argJson || "{}") } catch (e) { return "error: bad argument JSON" }
    var name = arg.stack
    if (!name || !Builder.NAME_RE.test(name)) return "error: invalid stack name"
    var background = arg.background === true
    var path = root.stacksDir + "/" + name + ".json"
    prepRunner.run([
      { label: "read " + name + ".json", argv: ["cat", path], collect: "raw" },
      { label: "list workspaces", argv: ["herdr", "workspace", "list"], collect: "wsjson" }
    ], {}, function(ctx) {
      var stack, errors, workspaces
      try {
        stack = Builder.normalize(JSON.parse(ctx.raw), root.homeDir)
        errors = Builder.validate(stack)
        workspaces = Builder.parseWorkspaces(ctx.wsjson)
      } catch (e) { root.notify("Rig: " + name, String(e.message || e)); return }
      if (errors.length) { root.notify("Rig: " + name + " is invalid", errors[0]); return }
      var existing = workspaces.byLabel[name]
      if (existing) {
        if (!background) runner.run([{ label: "focus workspace", argv: ["herdr", "workspace", "focus", existing.id] }],
          {}, function() {}, function(msg) { root.notify("Rig: " + name, root.herdrError(msg)) })
        return
      }
      root.executePlan(name, stack, background, workspaces.focusedActiveTabId)
    }, function(msg) {
      if (msg.indexOf("read ") === 0) root.notify("Rig", "no stack named \"" + name + "\" in " + root.stacksDir)
      else root.notify("Rig: " + name, root.herdrError(msg))
    })
    return "building " + name
  }

  function executePlan(name, stack, background, previousTabId) {
    var planObj = Builder.plan(name, stack)
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
      root.refresh()
    }, function(msg) {
      root.notify("Rig: " + name + " build failed", root.herdrError(msg))
    })
  }

  function killStack(argJson) {
    var arg
    try { arg = JSON.parse(argJson || "{}") } catch (e) { return "error: bad argument JSON" }
    var name = arg.stack
    if (!name) return "error: missing stack name"
    prepRunner.run([{ label: "list workspaces", argv: ["herdr", "workspace", "list"], collect: "wsjson" }],
      {}, function(ctx) {
        var existing
        try { existing = Builder.parseWorkspaces(ctx.wsjson).byLabel[name] } catch (e) { root.notify("Rig", String(e)); return }
        if (!existing) { root.notify("Rig", "\"" + name + "\" is not running"); return }
        runner.run([{ label: "close workspace", argv: ["herdr", "workspace", "close", existing.id] }],
          {}, function() { root.refresh() }, function(msg) { root.notify("Rig: " + name, root.herdrError(msg)) })
      }, function(msg) { root.notify("Rig", root.herdrError(msg)) })
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
      var json = JSON.stringify(result)
      prepRunner.run([{ label: "write listing", argv: ["bash", "-c", 'printf "%s" "$1" > "$2"', "rig-list", json, out] }],
        {}, function() {}, function(msg) { root.notify("Rig", root.herdrError(msg)) })
    }, function(msg) { root.notify("Rig", root.herdrError(msg)) })
    return "listing"
  }

  property var rows: []
  property int selectedIndex: 0
  property string uiState: "list"

  function refresh() {
    prepRunner.run([
      { label: "list stacks", argv: ["bash", "-c",
        'for f in "$HOME"/.config/rig/stacks/*.json; do [ -e "$f" ] || continue; printf "%s\\t%s\\n" "$(basename "$f" .json)" "$(base64 -w0 "$f")"; done'],
        collect: "listing" },
      { label: "list workspaces", argv: ["herdr", "workspace", "list"], collect: "wsjson" }
    ], {}, function(ctx) {
      var workspaces = { byLabel: {} }
      try { workspaces = Builder.parseWorkspaces(ctx.wsjson) } catch (e) { }
      var next = []
      Builder.parseStacksListing(ctx.listing || "", Qt.atob).forEach(function(entry) {
        var row = { type: "stack", name: entry.name, running: false, wsId: null, invalid: false, error: "" }
        try {
          var errors = Builder.validate(Builder.normalize(JSON.parse(entry.raw), root.homeDir))
          if (errors.length) { row.invalid = true; row.error = errors[0] }
        } catch (e) { row.invalid = true; row.error = String(e.message || e) }
        var ws = workspaces.byLabel[entry.name]
        if (ws) { row.running = true; row.wsId = ws.id }
        next.push(row)
      })
      next.sort(function(a, b) { return a.name < b.name ? -1 : 1 })
      next.push({ type: "new", name: "＋ New", running: false, wsId: null, invalid: false, error: "" })
      root.rows = next
      if (root.selectedIndex >= next.length) root.selectedIndex = next.length - 1
      if (root.selectedIndex < 0) root.selectedIndex = 0
    }, function(msg) {
      if (root.rows.length === 0) root.rows = [{ type: "new", name: "＋ New", running: false, wsId: null, invalid: false, error: "" }]
      root.notify("Rig", root.herdrError(msg))
    })
  }

  function herdrError(msg) {
    return /connect|connection refused|refused|socket|not running/i.test(msg) ? "no running Herdr server — start herdr first" : msg
  }

  function activateSelected(background) {
    var row = root.rows[root.selectedIndex]
    if (!row) return
    if (row.type === "new") { root.startPrompt("create", null); return }
    if (row.invalid) { root.notify("Rig: " + row.name + " is invalid", row.error); return }
    if (row.running) {
      root.dismiss()
      runner.run([{ label: "focus workspace", argv: ["herdr", "workspace", "focus", row.wsId] }],
        {}, function() {}, function(msg) { root.notify("Rig", root.herdrError(msg)) })
      return
    }
    var result = root.up(JSON.stringify({ stack: row.name, background: background }))
    if (result.indexOf("error") === 0) { root.notify("Rig", result); return }
    if (!background) root.dismiss()
  }

  property string confirmKillName: ""

  function confirmKill() {
    var row = root.rows[root.selectedIndex]
    if (!row || row.type !== "stack" || !row.running) return
    root.confirmKillName = row.name
    root.uiState = "confirm-kill"
  }

  function executeKill() {
    var name = root.confirmKillName
    root.confirmKillName = ""
    root.uiState = "list"
    if (!name) return
    root.killStack(JSON.stringify({ stack: name }))
  }

  property string promptText: ""
  property string promptMode: "create"   // "create" | "clone"
  property string promptSource: ""

  function startPrompt(mode, source) {
    root.promptMode = mode
    root.promptSource = source || ""
    root.promptText = ""
    root.uiState = "prompt-name"
  }

  function submitPrompt() {
    var name = root.promptText.trim()
    root.uiState = "list"
    if (!name) return
    var result = root.create(JSON.stringify({ name: name, from: root.promptSource || null }))
    if (result.indexOf("error") === 0) root.notify("Rig", result)
    else root.dismiss()
  }

  function create(argJson) {
    var arg
    try { arg = JSON.parse(argJson || "{}") } catch (e) { return "error: bad argument JSON" }
    var name = arg.name
    if (!name || !Builder.NAME_RE.test(name)) return "error: stack names must match A-Za-z0-9._-"
    var from = arg.from || null
    if (from !== null && !Builder.NAME_RE.test(from)) return "error: stack names must match A-Za-z0-9._-"
    var target = root.stacksDir + "/" + name + ".json"
    var source = from ? root.stacksDir + "/" + from + ".json"
                      : (Quickshell.env("HOME") + "/.config/omarchy/plugins/yordanbuilds.rig/template.json")
    prepRunner.run([
      { label: "create stack file", argv: ["bash", "-c",
        'set -e; mkdir -p "$(dirname "$1")"; [ ! -e "$1" ] || { echo "exists" >&2; exit 3; }; cp "$2" "$1"', "rig-new",
        target, source] }
    ], {}, function() {
      Quickshell.execDetached(["omarchy-launch-editor", target])
    }, function(msg) {
      if (msg.indexOf("exists") !== -1) root.notify("Rig", "\"" + name + "\" already exists — not overwriting")
      else root.notify("Rig", msg)
    })
    return "created " + name
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "rig-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: Color.menu.scrim }

    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      width: Math.min(Style.space(300), panel.width - Style.space(40))
      height: Math.min(content.implicitHeight + Style.spacing.panelPadding * 2, panel.height - Style.space(40))
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.uiState === "prompt-name") {
            if (event.key === Qt.Key_Escape) { root.uiState = "list"; event.accepted = true }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.submitPrompt(); event.accepted = true }
            else if (event.key === Qt.Key_Backspace) { root.promptText = root.promptText.slice(0, -1); event.accepted = true }
            else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
              root.promptText = root.promptText + event.text; event.accepted = true
            }
            return
          }
          if (root.uiState === "confirm-kill") {
            if (event.key === Qt.Key_Escape) { root.confirmKillName = ""; root.uiState = "list"; event.accepted = true }
            else if (event.key === Qt.Key_K || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.executeKill(); event.accepted = true
            }
            return
          }
          if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true }
          else if (event.key === Qt.Key_Down) {
            root.selectedIndex = Math.min(root.selectedIndex + 1, Math.max(0, root.rows.length - 1)); event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.selectedIndex = Math.max(root.selectedIndex - 1, 0); event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateSelected((event.modifiers & Qt.ShiftModifier) !== 0); event.accepted = true
          } else if (event.key === Qt.Key_K) {
            root.confirmKill(); event.accepted = true
          } else if (event.key === Qt.Key_N) {
            var row = root.rows[root.selectedIndex]
            if (row && row.type === "stack") root.startPrompt("clone", row.name)
            event.accepted = true
          }
        }

        Column {
          id: content
          width: parent.width
          spacing: Style.space(4)

          Text {
            width: parent.width
            text: "Rig"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
            font.bold: true
            bottomPadding: Style.space(6)
          }

          Repeater {
            model: root.rows
            delegate: Rectangle {
              required property var modelData
              required property int index
              width: content.width
              height: rowText.implicitHeight + Style.space(10)
              radius: Style.space(4)
              color: index === root.selectedIndex ? Color.menu.selectedBackground : "transparent"

              Text {
                id: rowText
                anchors.verticalCenter: parent.verticalCenter
                x: Style.space(8)
                width: parent.width - Style.space(16)
                elide: Text.ElideRight
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.subtitle
                color: index === root.selectedIndex ? Color.menu.selectedText : Color.menu.text
                text: {
                  if (modelData.type === "new") return modelData.name
                  var glyph = modelData.invalid ? "⚠" : (modelData.running ? "●" : "○")
                  if (root.uiState === "confirm-kill" && index === root.selectedIndex)
                    return glyph + "  kill " + modelData.name + "?  (k/Enter confirms, Esc cancels)"
                  return glyph + "  " + modelData.name
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                visible: modelData.type === "stack"
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.subtitle
                text: modelData.invalid ? "invalid" : (modelData.running ? "running" : "")
                color: modelData.invalid ? Color.urgent : Color.accent
              }
            }
          }

          Text {
            width: parent.width
            visible: root.uiState === "prompt-name"
            text: (root.promptMode === "clone" ? "New stack from " + root.promptSource + ": " : "New stack: ")
                  + root.promptText + "▏"
            color: Color.menu.selectedText
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.subtitle
            topPadding: Style.space(6)
          }
        }
      }
    }
  }
}
