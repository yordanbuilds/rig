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

## Install

```bash
omarchy plugin add https://github.com/yordanbuilds/rally.git --enable
ln -s ~/.config/omarchy/plugins/yordanbuilds.rally/bin/rally ~/.local/bin/rally   # optional CLI
```

Bind the picker to SUPER+R — add to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + R", "Rally", "omarchy-shell shell toggle yordanbuilds.rally '{}'")
```

Optional omarchy-menu entry — add to `~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
{ "name": "Rally", "icon": "󰞷", "action": "omarchy-shell shell toggle yordanbuilds.rally '{}'" }
```

## Usage

Stack files live in `~/.config/omarchy/stacks/<name>.json` — filename is the
stack name and the Herdr workspace label. In the picker: Enter builds (or
focuses, if running), Shift+Enter builds in the background, `k` kills after
an inline confirm, `n` clones the selected stack, `＋ New` starts from the
template. Focus lands on the last tab in the file — end with
`"terminal": null` for an empty terminal tab.

CLI: `rally`, `rally <stack>`, `rally up <stack> [-b]`, `rally kill <stack>`,
`rally new <name> [--from <stack>]`, `rally list`.

## Stack file reference

- `root` — required; the working directory for every tab. `~` expands.
- Any other top-level key is a tab: a string (one pane running that
  command), `null` (an empty terminal), or an object of `pane-name: command`
  entries, split evenly left-to-right.
- Extended pane form: `{ "run": "...", "after": "<pane>", "ready": "<text>" }`.
  `after` waits for the named pane (anywhere in the stack) to be ready.
  A pane is ready when its command exits successfully — or, if it declares
  `ready`, when that text appears in its output. Gates time out after 120s
  and start the pane anyway.

## License

[MIT](LICENSE)
