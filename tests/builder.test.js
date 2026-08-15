const test = require("node:test")
const assert = require("node:assert")
const B = require("../Builder.js")

const HOME = "/home/u"

test("normalize expands ~ in root", () => {
  const s = B.normalize({ root: "~/code/x", term: null }, HOME)
  assert.equal(s.root, "/home/u/code/x")
})

test("normalize: string tab becomes one pane named after the tab", () => {
  const s = B.normalize({ root: "/r", claude: "claude" }, HOME)
  assert.deepEqual(s.tabs, [{ name: "claude", panes: [{ name: "claude", key: "claude.claude", run: "claude", after: null, ready: null }] }])
})

test("normalize: null tab becomes one empty pane", () => {
  const s = B.normalize({ root: "/r", terminal: null }, HOME)
  assert.equal(s.tabs[0].panes[0].run, null)
})

test("normalize: object tab yields named panes in order", () => {
  const s = B.normalize({ root: "/r", server: { artisan: "php artisan serve", vite: "npm run dev" } }, HOME)
  assert.deepEqual(s.tabs[0].panes.map(p => p.name), ["artisan", "vite"])
  assert.equal(s.tabs[0].panes[1].key, "server.vite")
})

test("normalize: extended pane form carries run/after/ready", () => {
  const s = B.normalize({ root: "/r", t: { a: "cmd-a", b: { run: "cmd-b", after: "a", ready: "UP" } } }, HOME)
  const b = s.tabs[0].panes[1]
  assert.equal(b.run, "cmd-b"); assert.equal(b.after, "a"); assert.equal(b.ready, "UP")
})

test("normalize throws without root", () => {
  assert.throws(() => B.normalize({ t: "x" }, HOME), /root/)
})

test("normalize throws on extended pane without run", () => {
  assert.throws(() => B.normalize({ root: "/r", t: { a: { after: "b" } } }, HOME), /run/)
})

test("validate: after must resolve", () => {
  const s = B.normalize({ root: "/r", t: { a: { run: "x", after: "ghost" } } }, HOME)
  assert.match(B.validate(s)[0], /ghost/)
})

test("validate: after target ambiguous across tabs is an error", () => {
  const s = B.normalize({ root: "/r", t1: { a: "x" }, t2: { a: "y", b: { run: "z", after: "a" } } }, HOME)
  assert.match(B.validate(s)[0], /ambiguous/)
})

test("validate: unreferenced duplicate names are fine", () => {
  const s = B.normalize({ root: "/r", t1: { a: "x" }, t2: { a: "y" } }, HOME)
  assert.deepEqual(B.validate(s), [])
})

test("validate: cycle detection", () => {
  const s = B.normalize({ root: "/r", t: { a: { run: "x", after: "b" }, b: { run: "y", after: "a" } } }, HOME)
  assert.match(B.validate(s).join(" "), /cycle/i)
})

test("validate: self-reference is a cycle", () => {
  const s = B.normalize({ root: "/r", t: { a: { run: "x", after: "a" } } }, HOME)
  assert.match(B.validate(s).join(" "), /cycle|itself/i)
})

const APOYNT = {
  root: "~/code/apoynt",
  server: { artisan: "php artisan serve", vite: "npm run dev" },
  workers: { queues: "php artisan queue:work", scheduler: "php artisan schedule:work", reverb: "php artisan reverb:start" },
  terminal: null
}

test("plan: workspace create is first, with cwd/label/no-focus and full capture", () => {
  const stack = B.normalize(APOYNT, HOME)
  const plan = B.plan("apoynt", stack)
  const s0 = plan.steps[0]
  assert.deepEqual(s0.argv, ["herdr", "workspace", "create", "--cwd", "/home/u/code/apoynt", "--label", "apoynt", "--no-focus"])
  assert.deepEqual(s0.capture, {
    "ws": "result.workspace.workspace_id",
    "tab:server": "result.tab.tab_id",
    "pane:server.artisan": "result.root_pane.pane_id"
  })
})

test("plan: first tab is renamed, later tabs created with cwd and label", () => {
  const plan = B.plan("apoynt", B.normalize(APOYNT, HOME))
  assert.deepEqual(plan.steps[1].argv, ["herdr", "tab", "rename", "@{tab:server}", "server"])
  const tabCreate = plan.steps.find(s => s.argv[1] === "tab" && s.argv[2] === "create")
  assert.deepEqual(tabCreate.argv, ["herdr", "tab", "create", "--workspace", "@{ws}", "--cwd", "/home/u/code/apoynt", "--label", "workers", "--no-focus"])
  assert.deepEqual(tabCreate.capture, { "tab:workers": "result.tab.tab_id", "pane:workers.queues": "result.root_pane.pane_id" })
})

test("plan: even splits — 3 panes use ratios 0.333 then 0.5, splitting the previous new pane", () => {
  const plan = B.plan("apoynt", B.normalize(APOYNT, HOME))
  const splits = plan.steps.filter(s => s.argv[1] === "pane" && s.argv[2] === "split")
  const workers = splits.filter(s => s.argv[3].indexOf("workers") !== -1)
  assert.deepEqual(workers[0].argv, ["herdr", "pane", "split", "@{pane:workers.queues}", "--direction", "right", "--ratio", "0.333", "--no-focus"])
  assert.deepEqual(workers[0].capture, { "pane:workers.scheduler": "result.pane.pane_id" })
  assert.deepEqual(workers[1].argv, ["herdr", "pane", "split", "@{pane:workers.scheduler}", "--direction", "right", "--ratio", "0.5", "--no-focus"])
})

test("plan: every pane is renamed; empty panes get no run step", () => {
  const plan = B.plan("apoynt", B.normalize(APOYNT, HOME))
  const renames = plan.steps.filter(s => s.argv[1] === "pane" && s.argv[2] === "rename")
  assert.equal(renames.length, 6)  // artisan vite queues scheduler reverb terminal
  const runs = plan.steps.filter(s => s.argv[1] === "pane" && s.argv[2] === "run")
  assert.equal(runs.length, 5)     // terminal is null → no run
})

test("plan: all structure precedes all runs (two phases)", () => {
  const plan = B.plan("apoynt", B.normalize(APOYNT, HOME))
  const firstRun = plan.steps.findIndex(s => s.argv[2] === "run")
  const lastStructure = Math.max(...plan.steps.map((s, i) => s.argv[2] !== "run" ? i : -1))
  assert.ok(firstRun > lastStructure)
})

test("plan: gate prefixes dependent command; auto-marker appended to awaited exit-style pane", () => {
  const cfg = { root: "/r", server: { sail: "sail up -d", vite: { run: "npm run dev", after: "sail" } } }
  const plan = B.plan("s", B.normalize(cfg, HOME))
  const runs = plan.steps.filter(s => s.argv[2] === "run")
  const sail = runs.find(s => s.argv[3] === "@{pane:server.sail}")
  const vite = runs.find(s => s.argv[3] === "@{pane:server.vite}")
  assert.equal(sail.argv[4], 'sail up -d && echo RIG_"READY"')
  assert.equal(vite.argv[4], "\"$HOME\"/.config/omarchy/plugins/yordanbuilds.rig/bin/rig-wait-ready @{pane:server.sail} 'RIG_READY'; npm run dev")
})

test("plan: declared ready pattern is used instead of the marker, shell-quoted", () => {
  const cfg = { root: "/r", t: { srv: { run: "serve", ready: "Server running on port" }, w: { run: "work", after: "srv" } } }
  const plan = B.plan("s", B.normalize(cfg, HOME))
  const runs = plan.steps.filter(s => s.argv[2] === "run")
  const srv = runs.find(s => s.argv[3] === "@{pane:t.srv}")
  const w = runs.find(s => s.argv[3] === "@{pane:t.w}")
  assert.equal(srv.argv[4], "serve")  // ready-pattern pane gets NO marker
  assert.equal(w.argv[4], "\"$HOME\"/.config/omarchy/plugins/yordanbuilds.rig/bin/rig-wait-ready @{pane:t.srv} 'Server running on port'; work")
})

test("plan: lastTabKey names the final tab; focusSteps produce the finale", () => {
  const plan = B.plan("apoynt", B.normalize(APOYNT, HOME))
  assert.equal(plan.lastTabKey, "tab:terminal")
  assert.deepEqual(B.focusSteps(plan).map(s => s.argv), [
    ["herdr", "workspace", "focus", "@{ws}"],
    ["herdr", "tab", "focus", "@{tab:terminal}"]
  ])
})

test("shellQuote survives embedded single quotes", () => {
  assert.equal(B.shellQuote("it's"), "'it'\\''s'")
})

test("parseStacksListing decodes name/base64 lines", () => {
  const decode = s => Buffer.from(s, "base64").toString("utf8")
  const line = "apoynt\t" + Buffer.from('{"root":"/r"}').toString("base64")
  assert.deepEqual(B.parseStacksListing(line + "\n", decode), [{ name: "apoynt", raw: '{"root":"/r"}' }])
  assert.deepEqual(B.parseStacksListing("", decode), [])
})

test("parseWorkspaces maps labels and finds the focused active tab", () => {
  const json = JSON.stringify({ result: { workspaces: [
    { workspace_id: "w1", label: "apoynt", focused: false, active_tab_id: "w1:t3" },
    { workspace_id: "w2", label: "misc", focused: true, active_tab_id: "w2:t1" }
  ] } })
  const ws = B.parseWorkspaces(json)
  assert.equal(ws.byLabel["apoynt"].id, "w1")
  assert.equal(ws.byLabel["apoynt"].activeTabId, "w1:t3")
  assert.equal(ws.focusedActiveTabId, "w2:t1")
})

test("normalize throws when a tab name contains a reserved character", () => {
  assert.throws(() => B.normalize({ root: "/r", "web.admin": "cmd" }, HOME), /web\.admin/)
})

test("normalize throws when a pane name contains a reserved character", () => {
  assert.throws(() => B.normalize({ root: "/r", t: { "a{b": "cmd" } }, HOME), /a\{b/)
})

test("parseWorkspaces: byLabel has no prototype-chain pollution", () => {
  const ws = B.parseWorkspaces(JSON.stringify({ result: { workspaces: [] } }))
  assert.equal(ws.byLabel["constructor"], undefined)
})

test("substituteTokens replaces embedded tokens from ctx", () => {
  const out = B.substituteTokens(["herdr", "pane", "run", "@{pane:t.a}", "wait @{pane:t.b}; go"], { "pane:t.a": "w1:p1", "pane:t.b": "w1:p2" })
  assert.deepEqual(out, ["herdr", "pane", "run", "w1:p1", "wait w1:p2; go"])
})

test("substituteTokens throws on unresolved token", () => {
  assert.throws(() => B.substituteTokens(["@{ghost}"], {}), /unresolved token @\{ghost\}/)
})

test("walkPath resolves nested paths and tolerates gaps", () => {
  assert.equal(B.walkPath({ result: { pane: { pane_id: "w1:p9" } } }, "result.pane.pane_id"), "w1:p9")
  assert.equal(B.walkPath({ result: null }, "result.pane.pane_id"), undefined)
  assert.equal(B.walkPath({}, "missing.path"), undefined)
})
