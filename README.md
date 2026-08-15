# Rally

Declarative project stacks for [Herdr](https://herdr.dev), as an
[Omarchy](https://omarchy.org) shell plugin — the tmuxinator Herdr never had.

One JSON file per project describes your dev stack — server, vite, queue
workers, scheduler, whatever your mornings need. Press **SUPER+R**, pick a
stack, and Rally builds the whole Herdr workspace: tabs, evenly split panes,
commands running, dependent panes waiting for their upstreams to be ready.

```json
{
  "root": "~/code/apoynt",
  "server": { "artisan": "php artisan serve", "vite": "npm run dev" },
  "workers": {
    "queues": "php artisan queue:work",
    "scheduler": "php artisan schedule:work"
  },
  "terminal": null
}
```

Conventions over configuration: top-level keys are tabs, nested objects are
panes, a string is a command, `null` is an empty terminal. Need a pane to
wait for another? `{ "run": "npm run dev", "after": "sail" }`.

## Status

**In development.** The design is settled — stack file contract, picker UX,
build engine, CLI. Implementation is underway; installation instructions
land here when it ships.

Planned surface:

- Summonable picker (SUPER+R): `● running` / `○ stopped`, Enter to build or
  focus, `k` to kill, `n` / `＋ New` to scaffold a stack straight into your
  editor.
- `rally` CLI: `rally apoynt`, `rally new sell --from apoynt`, `rally list`.
- Zero dependencies — pure Quickshell/QML/JS, installed with
  `omarchy plugin add`.

## License

[MIT](LICENSE)
