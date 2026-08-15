# Rig

**Project stacks for [Herdr](https://herdr.dev). `rig acme` — and the whole workspace is up.**

You know the ritual. Open a terminal. Start the server. Split a pane, boot
Vite. New tab for the queue worker, another for the scheduler, one more to
actually work in. A couple of minutes of muscle memory before you've written a
single line of code — every single morning.

Rig ends the ritual. Describe your project's stack once, in one small
JSON file:

```json
{
  "root": "~/Projects/acme",
  "server": {
    "artisan": "php artisan serve",
    "vite": "npm run dev"
  },
  "workers": {
    "queues": "php artisan queue:work",
    "scheduler": "php artisan schedule:work",
    "reverb": "php artisan reverb:start"
  },
  "claude": "claude",
  "terminal": null
}
```

Then bring it up whenever you need it. Rig builds the whole workspace in
Herdr — tabs, evenly split panes, every process running, dependent panes
waiting for their upstreams:

```text
acme
├─ server     [ artisan ]  [ vite ]
├─ workers    [ queues ]  [ scheduler ]  [ reverb ]
├─ claude     [ claude ]
└─ terminal   [ shell ]              you land here, ready to work
```

The rules fit in your head: top-level keys are tabs, nested objects are
panes, a string is a command, `null` is an empty terminal. That's the whole
format. No daemon, no YAML, no dependencies — just a small plugin living in
your Omarchy shell.

## Installation

```bash
omarchy plugin add https://github.com/yordanbuilds/rig.git --enable
```

That's the whole thing. On first load, Rig sets itself up:

- <kbd>SUPER</kbd>+<kbd>R</kbd> opens your stacks in the Omarchy menu
- **Rig** appears in the Omarchy menu, under *Trigger*
- the `rig` command lands on your PATH

Everything setup adds is marked and yours — edit or remove any of it, and
Rig won't put it back.

Updating? `omarchy plugin update yordanbuilds.rig && omarchy restart shell`.

Leaving? `rig uninstall` removes every trace, keeping your stack files.

## The menu

Your stacks live where everything else on your desktop lives — in the
Omarchy menu, under *Trigger*.

| In the menu                   | What happens                                                 |
| ----------------------------- | ------------------------------------------------------------ |
| <kbd>SUPER</kbd>+<kbd>R</kbd> | Open your stacks in the menu                                 |
| type                          | Search                                                       |
| <kbd>Enter</kbd>              | Bring the stack up (opening Herdr if needed) — or jump to it |
| ✓                             | This stack is running                                        |
| `＋ New`                      | Name a stack, get a working template in your editor          |

And because stacks are ordinary menu entries, you don't even need
<kbd>SUPER</kbd>+<kbd>R</kbd>: open the Omarchy menu anywhere, type the
project's name, <kbd>Enter</kbd> — rigged.

## The CLI

Prefer to stay in the terminal? The menu is one face of `rig`; the terminal is the other:

```text
rig                           open the stack menu
rig acme                      build acme — or jump to it, if running
rig up acme -b                build in the background
rig kill acme                 close its workspace
rig new widgets --from acme   clone a stack definition into your editor
rig list                      JSON status of every stack, for scripting
```

Everything is idempotent. `rig acme` on a stack that's already running
simply takes you there — run it as many times as you like.

## Stack files

One file per stack in `~/.config/rig/stacks/` — the filename is the stack
name. `rig new` keeps the menu in sync; dropped a file in by hand?
`rig sync`.

| In the file             | What you get                                          |
| ----------------------- | ----------------------------------------------------- |
| `"root": "~/Projects/acme"` | Working directory for every tab — the one required key |
| `"server": "command"`   | A tab with one pane running the command               |
| `"terminal": null`      | A tab with an empty terminal                          |
| `"workers": { … }`      | A tab with one pane per entry, split evenly           |

Tabs are created in file order, and after a build **focus lands on the
last tab in the file** — end with `"terminal": null` and every morning
starts in a fresh shell, everything else already humming along.

### Waiting on other panes

Some panes shouldn't start until something else is ready. Say so with the
extended pane form:

```json
{
  "root": "~/Projects/widgets",
  "server": {
    "sail": "./vendor/bin/sail up -d",
    "vite": { "run": "npm run dev", "after": "sail" }
  },
  "workers": {
    "queues": { "run": "sail artisan queue:work", "after": "sail" }
  },
  "terminal": null
}
```

- **`after`** — wait for the named pane (anywhere in the stack) to be ready.
- **Ready means** the pane's command exited successfully — or, for
  long-running processes, that its `ready` text appeared in the output:

```json
"server": { "run": "php artisan serve", "ready": "Server running" },
"stripe": { "run": "stripe listen --forward-to localhost:8000", "after": "server" }
```

- **The wait is visible** — it happens right inside the dependent pane.
- **It can't hang your morning** — after two minutes the pane starts
  anyway.

## License

Rig is open-source software licensed under the [MIT license](LICENSE).
