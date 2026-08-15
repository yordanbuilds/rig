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
