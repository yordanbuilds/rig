// Builder.js — Rig's pure logic. Imported by QML (import "Builder.js" as Builder)
// and by node for tests. No QML/Qt APIs in this file.

var NAME_RE = /^[A-Za-z0-9._-]+$/

function normalize(config, home) {
  if (!config || typeof config !== "object" || Array.isArray(config))
    throw new Error("stack definition must be a JSON object")
  if (typeof config.root !== "string" || !config.root.trim())
    throw new Error("\"root\" is required and must be a path string")
  var root = config.root === "~" ? home : config.root.replace(/^~\//, home + "/")
  var tabs = []
  for (var tabName in config) {
    if (tabName === "root") continue
    if (/[.{}]/.test(tabName)) throw new Error("tab \"" + tabName + "\" must not contain \".\", \"{\", or \"}\"")
    var value = config[tabName]
    var panes = []
    if (value === null || typeof value === "string") {
      panes.push(makePane(tabName, tabName, value))
    } else if (typeof value === "object" && !Array.isArray(value)) {
      for (var paneName in value) panes.push(makePane(tabName, paneName, value[paneName]))
      if (panes.length === 0) throw new Error("tab \"" + tabName + "\" has no panes")
    } else {
      throw new Error("tab \"" + tabName + "\" must be a string, null, or an object")
    }
    tabs.push({ name: tabName, panes: panes })
  }
  if (tabs.length === 0) throw new Error("stack has no tabs")
  return { root: root, tabs: tabs }
}

function makePane(tabName, paneName, value) {
  if (/[.{}]/.test(paneName)) throw new Error("pane \"" + paneName + "\" must not contain \".\", \"{\", or \"}\"")
  var pane = { name: paneName, key: tabName + "." + paneName, run: null, after: null, ready: null }
  if (value === null) return pane
  if (typeof value === "string") { pane.run = value; return pane }
  if (typeof value === "object" && !Array.isArray(value)) {
    if (typeof value.run !== "string" || !value.run.trim())
      throw new Error("pane \"" + paneName + "\" uses the object form and must have \"run\"")
    pane.run = value.run
    pane.after = typeof value.after === "string" ? value.after : null
    pane.ready = typeof value.ready === "string" ? value.ready : null
    return pane
  }
  throw new Error("pane \"" + paneName + "\" must be a string, null, or an object")
}

function allPanes(stack) {
  var out = []
  for (var t = 0; t < stack.tabs.length; t++)
    for (var p = 0; p < stack.tabs[t].panes.length; p++) out.push(stack.tabs[t].panes[p])
  return out
}

function resolveAfter(stack, name) {
  var matches = allPanes(stack).filter(function(p) { return p.name === name })
  return matches.length === 1 ? matches[0] : null
}

function validate(stack) {
  var errors = []
  var panes = allPanes(stack)
  panes.forEach(function(pane) {
    if (!pane.after) return
    var matches = panes.filter(function(p) { return p.name === pane.after })
    if (matches.length === 0)
      errors.push("pane \"" + pane.key + "\": after target \"" + pane.after + "\" does not exist")
    else if (matches.length > 1)
      errors.push("pane \"" + pane.key + "\": after target \"" + pane.after + "\" is ambiguous (" +
        matches.map(function(m) { return m.key }).join(", ") + ")")
  })
  if (errors.length) return errors
  panes.forEach(function(pane) {
    var seen = {}
    var current = pane
    while (current && current.after) {
      if (seen[current.key]) { errors.push("dependency cycle involving \"" + pane.key + "\""); break }
      seen[current.key] = true
      current = resolveAfter(stack, current.after)
    }
  })
  return errors
}

var TIMEOUT_MS = 120000
var GATE = '"$HOME"/.config/omarchy/plugins/yordanbuilds.rig/bin/rig-wait-ready'
var MARKER = "RIG_READY"
var TYPED_MARKER = 'RIG_"READY"'   // typed into the pane; its echo output is MARKER, the typed line never matches

function shellQuote(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'"
}

function ratioFor(n, k) {  // k-th split (1-based) of a tab that ends with n panes
  var r = 1 / (n - k + 1)
  return String(Math.round(r * 1000) / 1000)
}

function isAwaited(stack, pane) {
  return allPanes(stack).some(function(p) { return p.after === pane.name })
}

function plan(name, stack) {
  var steps = []
  var firstTab = stack.tabs[0]
  var cap0 = { "ws": "result.workspace.workspace_id" }
  cap0["tab:" + firstTab.name] = "result.tab.tab_id"
  cap0["pane:" + firstTab.panes[0].key] = "result.root_pane.pane_id"
  steps.push({ label: "create workspace " + name,
    argv: ["herdr", "workspace", "create", "--cwd", stack.root, "--label", name, "--no-focus"],
    capture: cap0 })
  steps.push({ label: "name tab " + firstTab.name,
    argv: ["herdr", "tab", "rename", "@{tab:" + firstTab.name + "}", firstTab.name] })

  stack.tabs.forEach(function(tab, ti) {
    if (ti > 0) {
      var cap = {}
      cap["tab:" + tab.name] = "result.tab.tab_id"
      cap["pane:" + tab.panes[0].key] = "result.root_pane.pane_id"
      steps.push({ label: "create tab " + tab.name,
        argv: ["herdr", "tab", "create", "--workspace", "@{ws}", "--cwd", stack.root, "--label", tab.name, "--no-focus"],
        capture: cap })
    }
    for (var k = 1; k < tab.panes.length; k++) {
      var prev = tab.panes[k - 1], next = tab.panes[k], splitCap = {}
      splitCap["pane:" + next.key] = "result.pane.pane_id"
      steps.push({ label: "split pane " + next.key,
        argv: ["herdr", "pane", "split", "@{pane:" + prev.key + "}", "--direction", "right",
               "--ratio", ratioFor(tab.panes.length, k), "--no-focus"],
        capture: splitCap })
    }
  })

  allPanes(stack).forEach(function(pane) {
    steps.push({ label: "name pane " + pane.key,
      argv: ["herdr", "pane", "rename", "@{pane:" + pane.key + "}", pane.name] })
  })

  allPanes(stack).forEach(function(pane) {
    if (pane.run === null) return
    var cmd = pane.run
    if (isAwaited(stack, pane) && !pane.ready) cmd = cmd + " && echo " + TYPED_MARKER
    if (pane.after) {
      var target = resolveAfter(stack, pane.after)
      var pattern = target.ready ? target.ready : MARKER
      cmd = GATE + " @{pane:" + target.key + "} " + shellQuote(pattern) + "; " + cmd
    }
    steps.push({ label: "start " + pane.key,
      argv: ["herdr", "pane", "run", "@{pane:" + pane.key + "}", cmd] })
  })

  var lastTab = stack.tabs[stack.tabs.length - 1]
  return { steps: steps, wsKey: "ws", lastTabKey: "tab:" + lastTab.name }
}

function focusSteps(planObj) {
  return [
    { label: "focus workspace", argv: ["herdr", "workspace", "focus", "@{ws}"] },
    { label: "focus last tab", argv: ["herdr", "tab", "focus", "@{" + planObj.lastTabKey + "}"] }
  ]
}

function parseStacksListing(text, decode) {
  var out = []
  String(text).split("\n").forEach(function(line) {
    if (!line.trim()) return
    var tab = line.indexOf("\t")
    if (tab === -1) return
    out.push({ name: line.slice(0, tab), raw: decode(line.slice(tab + 1)) })
  })
  return out
}

function parseWorkspaces(jsonText) {
  var byLabel = Object.create(null), focusedActiveTabId = null
  var list = JSON.parse(jsonText).result.workspaces || []
  list.forEach(function(ws) {
    byLabel[ws.label] = { id: ws.workspace_id, activeTabId: ws.active_tab_id || null }
    if (ws.focused) focusedActiveTabId = ws.active_tab_id || null
  })
  return { byLabel: byLabel, focusedActiveTabId: focusedActiveTabId }
}

function substituteTokens(argv, ctx) {
  return argv.map(function(a) {
    return a.replace(/@\{([^}]+)\}/g, function(_, key) {
      if (!(key in ctx)) throw new Error("unresolved token @{" + key + "}")
      return ctx[key]
    })
  })
}

function walkPath(obj, dottedPath) {
  var parts = dottedPath.split(".")
  var current = obj
  for (var i = 0; i < parts.length; i++) {
    if (current === null || current === undefined) return undefined
    current = current[parts[i]]
  }
  return current
}

if (typeof module !== "undefined" && module.exports)
  module.exports = { NAME_RE: NAME_RE, normalize: normalize, validate: validate, resolveAfter: resolveAfter, allPanes: allPanes, plan: plan, focusSteps: focusSteps, shellQuote: shellQuote, parseStacksListing: parseStacksListing, parseWorkspaces: parseWorkspaces, TIMEOUT_MS: TIMEOUT_MS, MARKER: MARKER, TYPED_MARKER: TYPED_MARKER, isAwaited: isAwaited, substituteTokens: substituteTokens, walkPath: walkPath }
