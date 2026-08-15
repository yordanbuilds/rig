import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var steps: []
  property var ctx: ({})
  property int index: 0
  property var doneCallback: null
  property var errorCallback: null
  property bool busy: false
  property string lastStdout: ""

  function run(steps, ctx, onDone, onError) {
    if (root.busy) { if (onError) onError("runner busy — another build is in progress"); return }
    root.steps = steps
    root.ctx = ctx || ({})
    root.index = 0
    root.doneCallback = onDone
    root.errorCallback = onError
    root.busy = true
    next()
  }

  function substitute(argv) {
    return argv.map(function(a) {
      return a.replace(/@\{([^}]+)\}/g, function(_, key) {
        if (!(key in root.ctx)) throw new Error("unresolved token @{" + key + "}")
        return root.ctx[key]
      })
    })
  }

  function next() {
    if (root.index >= root.steps.length) {
      root.busy = false
      if (root.doneCallback) root.doneCallback(root.ctx)
      return
    }
    var step = root.steps[root.index]
    var argv
    try { argv = substitute(step.argv) } catch (e) { fail(step.label + ": " + e.message); return }
    root.lastStdout = ""
    proc.command = argv
    proc.running = true
  }

  function fail(message) {
    root.busy = false
    if (root.errorCallback) root.errorCallback(message)
  }

  function walk(obj, dottedPath) {
    var parts = dottedPath.split(".")
    var current = obj
    for (var i = 0; i < parts.length; i++) {
      if (current === null || current === undefined) return undefined
      current = current[parts[i]]
    }
    return current
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
          var value = root.walk(parsed, step.capture[key])
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
