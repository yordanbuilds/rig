// Builder.mjs — Rig's pure logic. Imported by QML (import "Builder.mjs" as Builder)
// and by node for tests. No QML/Qt APIs in this file.

export const NAME_RE = /^[A-Za-z0-9._-]+$/

export function normalize(config, home) {
  if (!config || typeof config !== "object" || Array.isArray(config))
    throw new Error("stack definition must be a JSON object")
  if (typeof config.root !== "string" || !config.root.trim())
    throw new Error('"root" is required and must be a path string')
  const root = config.root === "~" ? home : config.root.replace(/^~\//, `${home}/`)
  const tabs = []
  for (const [tabName, value] of Object.entries(config)) {
    if (tabName === "root") continue
    if (/[.{}]/.test(tabName)) throw new Error(`tab "${tabName}" must not contain ".", "{", or "}"`)
    const panes = []
    if (value === null || typeof value === "string") {
      panes.push(makePane(tabName, tabName, value))
    } else if (typeof value === "object" && !Array.isArray(value)) {
      for (const [paneName, paneValue] of Object.entries(value)) panes.push(makePane(tabName, paneName, paneValue))
      if (panes.length === 0) throw new Error(`tab "${tabName}" has no panes`)
    } else {
      throw new Error(`tab "${tabName}" must be a string, null, or an object`)
    }
    tabs.push({ name: tabName, panes })
  }
  if (tabs.length === 0) throw new Error("stack has no tabs")
  return { root, tabs }
}

function makePane(tabName, paneName, value) {
  if (/[.{}]/.test(paneName)) throw new Error(`pane "${paneName}" must not contain ".", "{", or "}"`)
  const pane = { name: paneName, key: `${tabName}.${paneName}`, run: null, after: null, ready: null }
  if (value === null) return pane
  if (typeof value === "string") { pane.run = value; return pane }
  if (typeof value === "object" && !Array.isArray(value)) {
    if (typeof value.run !== "string" || !value.run.trim())
      throw new Error(`pane "${paneName}" uses the object form and must have "run"`)
    pane.run = value.run
    pane.after = typeof value.after === "string" ? value.after : null
    pane.ready = typeof value.ready === "string" ? value.ready : null
    return pane
  }
  throw new Error(`pane "${paneName}" must be a string, null, or an object`)
}

export function allPanes(stack) {
  const out = []
  for (const tab of stack.tabs) out.push(...tab.panes)
  return out
}

export function resolveAfter(stack, name) {
  const matches = allPanes(stack).filter(p => p.name === name)
  return matches.length === 1 ? matches[0] : null
}

export function validate(stack) {
  const errors = []
  const panes = allPanes(stack)
  for (const pane of panes) {
    if (!pane.after) continue
    const matches = panes.filter(p => p.name === pane.after)
    if (matches.length === 0)
      errors.push(`pane "${pane.key}": after target "${pane.after}" does not exist`)
    else if (matches.length > 1)
      errors.push(`pane "${pane.key}": after target "${pane.after}" is ambiguous (${matches.map(m => m.key).join(", ")})`)
  }
  if (errors.length) return errors
  for (const pane of panes) {
    const seen = new Set()
    let current = pane
    while (current && current.after) {
      if (seen.has(current.key)) { errors.push(`dependency cycle involving "${pane.key}"`); break }
      seen.add(current.key)
      current = resolveAfter(stack, current.after)
    }
  }
  return errors
}

export const TIMEOUT_MS = 120000
const GATE = '"$HOME"/.config/omarchy/plugins/yordanbuilds.rig/bin/rig-wait-ready'

export function shellQuote(s) {
  return `'${String(s).replace(/'/g, "'\\''")}'`
}

function ratioFor(n, k) {  // k-th split (1-based) of a tab that ends with n panes
  const r = 1 / (n - k + 1)
  return String(Math.round(r * 1000) / 1000)
}

export function isAwaited(stack, pane) {
  return allPanes(stack).some(p => p.after === pane.name)
}

function readyFile(nonce, paneKey) {
  return `/tmp/rig-ready-${nonce}-@{pane:${paneKey}}`
}

export function plan(name, stack, nonce = "0") {
  const steps = []
  const firstTab = stack.tabs[0]
  steps.push({ label: `create workspace ${name}`,
    argv: ["herdr", "workspace", "create", "--cwd", stack.root, "--label", name, "--no-focus"],
    capture: {
      "ws": "result.workspace.workspace_id",
      [`tab:${firstTab.name}`]: "result.tab.tab_id",
      [`pane:${firstTab.panes[0].key}`]: "result.root_pane.pane_id"
    } })
  steps.push({ label: `name tab ${firstTab.name}`,
    argv: ["herdr", "tab", "rename", `@{tab:${firstTab.name}}`, firstTab.name] })

  stack.tabs.forEach((tab, ti) => {
    if (ti > 0) {
      steps.push({ label: `create tab ${tab.name}`,
        argv: ["herdr", "tab", "create", "--workspace", "@{ws}", "--cwd", stack.root, "--label", tab.name, "--no-focus"],
        capture: {
          [`tab:${tab.name}`]: "result.tab.tab_id",
          [`pane:${tab.panes[0].key}`]: "result.root_pane.pane_id"
        } })
    }
    for (let k = 1; k < tab.panes.length; k++) {
      const prev = tab.panes[k - 1], next = tab.panes[k]
      steps.push({ label: `split pane ${next.key}`,
        argv: ["herdr", "pane", "split", `@{pane:${prev.key}}`, "--direction", "right",
               "--ratio", ratioFor(tab.panes.length, k), "--no-focus"],
        capture: { [`pane:${next.key}`]: "result.pane.pane_id" } })
    }
  })

  for (const pane of allPanes(stack)) {
    steps.push({ label: `name pane ${pane.key}`,
      argv: ["herdr", "pane", "rename", `@{pane:${pane.key}}`, pane.name] })
  }

  for (const pane of allPanes(stack)) {
    if (pane.run === null) continue
    let cmd = pane.run
    if (isAwaited(stack, pane) && !pane.ready) cmd = `${cmd} && touch ${readyFile(nonce, pane.key)}`
    if (pane.after) {
      const target = resolveAfter(stack, pane.after)
      const signal = target.ready ? shellQuote(target.ready) : readyFile(nonce, target.key)
      cmd = `${GATE} @{pane:${target.key}} ${signal}; ${cmd}`
    }
    steps.push({ label: `start ${pane.key}`,
      argv: ["herdr", "pane", "run", `@{pane:${pane.key}}`, cmd] })
  }

  const lastTab = stack.tabs[stack.tabs.length - 1]
  return { steps, wsKey: "ws", lastTabKey: `tab:${lastTab.name}` }
}

export function focusSteps(planObj) {
  return [
    { label: "focus workspace", argv: ["herdr", "workspace", "focus", "@{ws}"] },
    { label: "focus last tab", argv: ["herdr", "tab", "focus", `@{${planObj.lastTabKey}}`] }
  ]
}

export function parseStacksListing(text, decode) {
  const out = []
  for (const line of String(text).split("\n")) {
    if (!line.trim()) continue
    const tab = line.indexOf("\t")
    if (tab === -1) continue
    out.push({ name: line.slice(0, tab), raw: decode(line.slice(tab + 1)) })
  }
  return out
}

export function parseWorkspaces(jsonText) {
  const byLabel = Object.create(null)
  let focusedActiveTabId = null
  const list = JSON.parse(jsonText).result.workspaces || []
  for (const ws of list) {
    byLabel[ws.label] = { id: ws.workspace_id, activeTabId: ws.active_tab_id || null }
    if (ws.focused) focusedActiveTabId = ws.active_tab_id || null
  }
  return { byLabel, focusedActiveTabId }
}

export function substituteTokens(argv, ctx) {
  return argv.map(a => a.replace(/@\{([^}]+)\}/g, (_, key) => {
    if (!(key in ctx)) throw new Error(`unresolved token @{${key}}`)
    return ctx[key]
  }))
}

export function walkPath(obj, dottedPath) {
  let current = obj
  for (const part of dottedPath.split(".")) {
    if (current === null || current === undefined) return undefined
    current = current[part]
  }
  return current
}
