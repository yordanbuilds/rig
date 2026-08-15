# Contributing

Issues and pull requests are welcome.

## Development

Rig runs from its checkout. Clone it where Omarchy loads plugins from:

```bash
git clone https://github.com/yordanbuilds/rig.git ~/.config/omarchy/plugins/yordanbuilds.rig
omarchy plugin enable yordanbuilds.rig
```

The shell does not reload already-loaded plugin QML — run
`omarchy restart shell` after editing `.qml` files. Bash scripts in `bin/`
take effect immediately.

## Tests

```bash
node --test "tests/**/*.test.mjs"  # Builder unit tests
bash tests/scripts.test.sh          # bash surface, sandboxed — no live session needed
bash tests/qml-smoke.sh             # Builder inside the real QML engine (needs qt6-declarative)
bash tests/live.sh                  # smoke against your running Herdr (skips if down)
```

The first three run in CI on every push and pull request; a PR needs them
green. Please add tests for behavior you change.

Builder.mjs is loaded by two JavaScript engines: node (tests) and Qt's QML
engine (the plugin itself). The QML engine parses less of the language — no
object spread/rest, no async functions, no `flatMap`/`at`/`fromEntries` — and
a parse error there means the plugin silently fails to load. `qml-smoke.sh`
exists to catch exactly that, so run it before pushing JavaScript changes.
