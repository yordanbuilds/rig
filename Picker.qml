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

  readonly property string pluginId: (manifest && manifest.id) || "yordanbuilds.rally"

  function open(payloadJson) {
    root.opened = true
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

  property string stacksDir: Quickshell.env("HOME") + "/.config/omarchy/stacks"
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
      } catch (e) { root.notify("Rally: " + name, String(e.message || e)); return }
      if (errors.length) { root.notify("Rally: " + name + " is invalid", errors[0]); return }
      var existing = workspaces.byLabel[name]
      if (existing) {
        if (!background) runner.run([{ label: "focus workspace", argv: ["herdr", "workspace", "focus", existing.id] }],
          {}, function() {}, function(msg) { root.notify("Rally: " + name, msg) })
        return
      }
      root.executePlan(name, stack, background, workspaces.focusedActiveTabId)
    }, function(msg) {
      if (msg.indexOf("read ") === 0) root.notify("Rally", "no stack named \"" + name + "\" in " + root.stacksDir)
      else root.notify("Rally: " + name, msg)
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
        ], {}, function() {}, function(msg) { root.notify("Rally: " + name, msg) })
      }
      root.refresh()
    }, function(msg) {
      root.notify("Rally: " + name + " build failed", msg)
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
        try { existing = Builder.parseWorkspaces(ctx.wsjson).byLabel[name] } catch (e) { root.notify("Rally", String(e)); return }
        if (!existing) { root.notify("Rally", "\"" + name + "\" is not running"); return }
        runner.run([{ label: "close workspace", argv: ["herdr", "workspace", "close", existing.id] }],
          {}, function() { root.refresh() }, function(msg) { root.notify("Rally: " + name, msg) })
      }, function(msg) { root.notify("Rally", msg) })
    return "killing " + name
  }

  function kill(argJson) { return killStack(argJson) }

  function refresh() { }  // populated in Task 5; safe no-op until then

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "rally-picker"
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
          if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          }
        }

        Column {
          id: content
          width: parent.width
          spacing: Style.space(8)

          Text {
            width: parent.width
            text: "Rally"
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
        }
      }
    }
  }
}
