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
  "root": "~/code/acme",
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
└─ terminal   [ shell ]              ← you land here, ready to work
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

- <kbd>SUPER</kbd>+<kbd>R</kbd> opens the picker
- **Rig** appears in the Omarchy menu, under *Trigger*
- the `rig` command lands on your PATH

Everything setup adds is marked and yours — edit or remove any of it, and
Rig won't put it back.

Leaving? `rig uninstall` removes every trace, keeping your stack files.

## The picker

Hit <kbd>SUPER</kbd>+<kbd>R</kbd> and every stack you've defined is right
there, with its live status. Type to search, just like the Omarchy menu.
Stacks are just files in `~/.config/rig/stacks/` — the filename is the
stack name. Drop one in, it shows up.

| Key                                | What happens                                                   |
| ---------------------------------- | -------------------------------------------------------------- |
| type                               | Filter the list                                                |
| <kbd>Enter</kbd>                   | Build the stack — or jump to it, if it's already running       |
| <kbd>Shift</kbd>+<kbd>Enter</kbd>  | Build it in the background and stay where you are              |
| <kbd>Delete</kbd>                  | Kill a running stack — <kbd>Enter</kbd> confirms               |
| <kbd>Ctrl</kbd>+<kbd>N</kbd>       | New stack, cloned from the selected one, opened in your editor |
| <kbd>↑</kbd> <kbd>↓</kbd>          | Navigate                                                       |
| <kbd>Esc</kbd>                     | Clear the search — or close                                    |

`＋ New` scaffolds a stack from a working template and drops you straight
into your editor. Broke a definition? The picker shows it as ``, and
<kbd>Enter</kbd> tells you exactly what's wrong.

## The CLI

Prefer to stay in the terminal? Everything the picker does, `rig` does too:

```text
rig                           open the picker
rig acme                      build acme — or jump to it, if running
rig up acme -b                build in the background
rig kill acme                 close its workspace
rig new widgets --from acme   clone a stack definition into your editor
rig list                      JSON status of every stack, for scripting
```

Everything is idempotent. `rig acme` on a stack that's already running
simply takes you there — run it as many times as you like.

## Stack files

- `root` is the only required key: the working directory for every tab.
  `~` expands, as it should.
- Every other top-level key is a **tab**, created in file order. A string
  runs one command. `null` opens an empty terminal. An object opens one
  pane per entry, split evenly.
- After a build, focus lands on the **last tab in the file** — end with
  `"terminal": null` and every morning starts in a fresh shell, with
  everything else already humming along.

### Waiting on other panes

Some panes shouldn't start until something else is ready. Say so:

```json
{
  "root": "~/code/widgets",
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

A pane is ready when its command finishes. For long-running processes,
tell Rig what to look for instead:

```json
"server": { "run": "php artisan serve", "ready": "Server running" },
"stripe": { "run": "stripe listen --forward-to localhost:8000", "after": "server" }
```

The waiting happens right inside the dependent pane, where you can watch
it. And if an upstream never reports ready, Rig starts the pane anyway
after two minutes — a slow dependency shouldn't leave half your workspace
dead.

## License

Rig is open-source software licensed under the [MIT license](LICENSE).
