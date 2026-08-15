import QtQuick
import Quickshell
import Quickshell.Io
import "Builder.js" as Builder

Item {
  id: root

  property var steps: []
  property var ctx: ({})
  property int index: 0
  property var doneCallback: null
  property var errorCallback: null
  property bool busy: false
  property string lastStdout: ""
  property var pending: []

  function run(steps, ctx, onDone, onError) {
    if (root.busy) { root.pending.push({ steps: steps, ctx: ctx, onDone: onDone, onError: onError }); return }
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
    var job = root.pending.shift()
    root.run(job.steps, job.ctx, job.onDone, job.onError)
  }

  function next() {
    if (root.index >= root.steps.length) {
      root.busy = false
      if (root.doneCallback) root.doneCallback(root.ctx)
      Qt.callLater(root.startNext)
      return
    }
    var step = root.steps[root.index]
    var argv
    try { argv = Builder.substituteTokens(step.argv, root.ctx) } catch (e) { fail(step.label + ": " + e.message); return }
    root.lastStdout = ""
    proc.command = argv
    proc.running = true
  }

  function fail(message) {
    root.busy = false
    if (root.errorCallback) root.errorCallback(message)
    Qt.callLater(root.startNext)
  }

  Process {
    id: proc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.lastStdout = text }
    stderr: StdioCollector { id: errOut; waitForEnd: true }
    onExited: function(exitCode) {
      var step = root.steps[root.index]
      if (exitCode !== 0) {
        root.fail(step.label + " failed (exit " + exitCode + "): " + (errOut.text || root.lastStdout).slice(0, 400))
        return
      }
      if (step.collect) root.ctx[step.collect] = root.lastStdout
      if (step.capture) {
        var parsed
        try { parsed = JSON.parse(root.lastStdout) } catch (e) {
          root.fail(step.label + ": herdr returned non-JSON: " + root.lastStdout.slice(0, 200)); return
        }
        for (var key in step.capture) {
          var value = Builder.walkPath(parsed, step.capture[key])
          if (value === undefined || value === null) {
            root.fail(step.label + ": missing " + step.capture[key] + " in response"); return
          }
          root.ctx[key] = String(value)
        }
      }
      root.index++
      root.next()
    }
  }
}
