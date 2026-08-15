import QtQuick
import "../../Builder.mjs" as Builder

// Runs Builder's logic inside the real QML engine (the one Quickshell embeds).
// Node parses newer JavaScript than Qt does, so `node --test` alone cannot
// catch syntax that would make the plugin silently fail to load. Run via
// tests/qml-smoke.sh.
Item {
  Component.onCompleted: {
    const failures = []
    const ok = (label, cond) => { if (!cond) failures.push(label) }

    const stack = Builder.normalize({
      root: "~/code/demo",
      server: { app: { run: "serve", ready: "ready in" }, vite: { run: "npm run dev", after: "app" } },
      terminal: null
    }, "/home/u")
    ok("root expands ~", stack.root === "/home/u/code/demo")
    ok("two tabs", stack.tabs.length === 2)
    ok("validate clean", Builder.validate(stack).length === 0)

    const plan = Builder.plan("demo", stack, "N")
    ok("workspace create first", plan.steps[0].argv.join(" ").startsWith("herdr workspace create"))
    const runs = plan.steps.filter(s => s.argv[2] === "run")
    ok("gate prefixes dependent", runs.some(s => s.argv[4].includes("rig-wait-ready")))
    ok("ready pattern quoted", runs.some(s => s.argv[4].includes("'ready in'")))
    ok("focus steps", Builder.focusSteps(plan).length === 2)

    ok("NAME_RE accepts", Builder.NAME_RE.test("my-stack.2"))
    ok("NAME_RE rejects", !Builder.NAME_RE.test("bad name"))

    const ws = Builder.parseWorkspaces(JSON.stringify({ result: { workspaces: [
      { workspace_id: "w1", label: "demo", focused: true, active_tab_id: "w1:t2" }
    ] } }))
    ok("parseWorkspaces", ws.byLabel["demo"].id === "w1" && ws.focusedActiveTabId === "w1:t2")

    ok("substituteTokens", Builder.substituteTokens(["@{a}"], { a: "x" })[0] === "x")
    ok("walkPath", Builder.walkPath({ a: { b: 1 } }, "a.b") === 1)
    ok("shellQuote", Builder.shellQuote("it's") === "'it'\\''s'")

    if (failures.length > 0) {
      console.error("SMOKE FAIL: " + failures.join("; "))
      Qt.exit(1)
    } else {
      console.log("SMOKE OK")
      Qt.quit()
    }
  }
}
