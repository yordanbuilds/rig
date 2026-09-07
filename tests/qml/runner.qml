import QtQuick

// Exercises HerdrRunner under the real Quickshell engine: the one place its
// Process, parsers, and kill path can actually run. Quickshell only loads QML
// from the config folder, so tests/runner-smoke.sh stages this file next to a
// copy of HerdrRunner.qml and Builder.mjs and runs it there.
//
// What it pins down: a child that floods stdout or stderr is cut off at the
// runner's byte cap and reported as a failure instead of being buffered until
// the shell runs out of memory; a quiet step collects "" rather than the
// previous step's output; and the runner keeps working after it had to kill.
Item {
  id: root

  property var failures: []
  function ok(label, cond) { if (!cond) root.failures.push(label) }

  HerdrRunner { id: runner }

  Component.onCompleted: normal()

  // Capture and collect still work the way Picker relies on them.
  function normal() {
    runner.run([
      { label: "emit json", argv: ["sh", "-c", "printf '{\"result\":{\"id\":\"w1\"}}'"],
        capture: { ws: "result.id" }, collect: "raw" },
      { label: "quiet", argv: ["true"], collect: "quiet" }
    ], {}, ctx => {
      ok("capture walks the JSON", ctx.ws === "w1")
      ok("collect keeps stdout", ctx.raw.indexOf('"w1"') >= 0)
      ok("a quiet step collects nothing, not the previous step's stdout", ctx.quiet === "")
      floodStdout()
    }, msg => { ok("normal steps must not fail: " + msg, false); floodStdout() })
  }

  // An endless producer on stdout is killed at the cap and reported.
  function floodStdout() {
    runner.run([{ label: "flood", argv: ["cat", "/dev/zero"] }], {},
      ctx => { ok("a stdout flood must fail", false); floodStderr() },
      msg => {
        ok("stdout flood names the step and stream: " + msg, /^flood: stdout exceeded \d+ bytes/.test(msg))
        ok("runner is free after killing", !runner.busy)
        floodStderr()
      })
  }

  // Same on stderr, which is buffered for error messages.
  function floodStderr() {
    runner.run([{ label: "errflood", argv: ["sh", "-c", "exec cat /dev/zero >&2"] }], {},
      ctx => { ok("a stderr flood must fail", false); failing() },
      msg => {
        ok("stderr flood names the step and stream: " + msg, /^errflood: stderr exceeded \d+ bytes/.test(msg))
        failing()
      })
  }

  // A failing step reports its own stderr, not what an earlier step left behind.
  function failing() {
    runner.run([{ label: "boom", argv: ["sh", "-c", "echo nope >&2; exit 3"] }], {},
      ctx => { ok("a non-zero exit must fail", false); recovers() },
      msg => { ok("exit failure carries its own stderr: " + msg, msg === "boom failed (exit 3): nope\n"); recovers() })
  }

  // After a kill and a failure, a clean run still goes through.
  function recovers() {
    runner.run([{ label: "again", argv: ["sh", "-c", "printf '{\"a\":{\"b\":\"z\"}}'"], capture: { v: "a.b" } }], {},
      ctx => { ok("runner recovers after a kill", ctx.v === "z"); finish() },
      msg => { ok("runner recovers after a kill: " + msg, false); finish() })
  }

  function finish() {
    if (root.failures.length > 0) {
      console.error("RUNNER FAIL: " + root.failures.join("; "))
      Qt.exit(1)
    } else {
      console.log("RUNNER OK")
      Qt.quit()
    }
  }
}
