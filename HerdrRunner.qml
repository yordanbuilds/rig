import QtQuick
import Quickshell.Io
import "Builder.mjs" as Builder

Item {
  id: root

  property var steps: []
  property var ctx: ({})
  property int index: 0
  property var doneCallback: null
  property var errorCallback: null
  property bool busy: false
  property var pending: []

  // A step's whole stdout and stderr sit in the shell's memory until the
  // step ends — so a child that keeps printing is killed once a stream
  // passes this many bytes, rather than growing the shell until the kernel
  // does it. Herdr answers in a few hundred bytes; a stack file is smaller.
  readonly property int outputCap: 1048576

  // Per-step copies of both streams. A collector keeps its last buffer after
  // a stream ends, so a step that printed nothing would otherwise read what
  // the previous step printed.
  property string stdoutText: ""
  property string stderrText: ""
  property string overflowed: ""

  function run(steps, ctx, onDone, onError) {
    if (root.busy) { root.pending.push({ steps, ctx, onDone, onError }); return }
    root.steps = steps
    root.ctx = ctx || ({})
    root.index = 0
    root.doneCallback = onDone
    root.errorCallback = onError
    root.busy = true
    next()
  }

  function startNext() {
    if (root.pending.length === 0) return
    const job = root.pending.shift()
    root.run(job.steps, job.ctx, job.onDone, job.onError)
  }

  function next() {
    if (root.index >= root.steps.length) {
      root.busy = false
      if (root.doneCallback) root.doneCallback(root.ctx)
      Qt.callLater(root.startNext)
      return
    }
    const step = root.steps[root.index]
    let argv
    try { argv = Builder.substituteTokens(step.argv, root.ctx) } catch (e) { fail(`${step.label}: ${e.message}`); return }
    root.stdoutText = ""
    root.stderrText = ""
    root.overflowed = ""
    proc.command = argv
    proc.running = true
  }

  function fail(message) {
    root.busy = false
    if (root.errorCallback) root.errorCallback(message)
    Qt.callLater(root.startNext)
  }

  // Runs on every chunk a stream delivers. Past the cap the child is killed;
  // chunks already in the pipe still land afterwards, so the first overflow
  // is the one reported and the signal is sent once.
  function guard(stream, collector) {
    if (root.overflowed) return
    if (collector.data.byteLength > root.outputCap) {
      root.overflowed = stream
      proc.signal(9)
      return
    }
    if (stream === "stdout") root.stdoutText = collector.text
    else root.stderrText = collector.text
  }

  Process {
    id: proc
    stdout: StdioCollector { id: outStream; waitForEnd: false; onDataChanged: root.guard("stdout", outStream) }
    stderr: StdioCollector { id: errStream; waitForEnd: false; onDataChanged: root.guard("stderr", errStream) }
    onExited: function(exitCode) {
      const step = root.steps[root.index]
      if (root.overflowed) {
        root.fail(`${step.label}: ${root.overflowed} exceeded ${root.outputCap} bytes, killed`)
        return
      }
      if (exitCode !== 0) {
        root.fail(`${step.label} failed (exit ${exitCode}): ` + (root.stderrText || root.stdoutText).slice(0, 400))
        return
      }
      if (step.collect) root.ctx[step.collect] = root.stdoutText
      if (step.capture) {
        let parsed
        try { parsed = JSON.parse(root.stdoutText) } catch (e) {
          root.fail(`${step.label}: herdr returned non-JSON: ` + root.stdoutText.slice(0, 200)); return
        }
        for (const key in step.capture) {
          const value = Builder.walkPath(parsed, step.capture[key])
          if (value === undefined || value === null) {
            root.fail(`${step.label}: missing ${step.capture[key]} in response`); return
          }
          root.ctx[key] = String(value)
        }
      }
      root.index++
      root.next()
    }
  }
}
