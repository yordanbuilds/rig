// Builder.js — Rally's pure logic. Imported by QML (import "Builder.js" as Builder)
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

if (typeof module !== "undefined" && module.exports)
  module.exports = { NAME_RE: NAME_RE, normalize: normalize, validate: validate, resolveAfter: resolveAfter, allPanes: allPanes }
