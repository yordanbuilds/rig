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
- **Rig** appears in the Omarchy menu, under _Trigger_
- the `rig` command lands on your PATH

Everything setup adds is marked and yours — edit or remove any of it, and
Rig won't put it back.

Updating? `omarchy plugin update yordanbuilds.rig && omarchy restart shell`.

Leaving? `rig uninstall` removes every trace, keeping your stack files.

## The menu

Your stacks are entries in the Omarchy menu, under _Trigger_.

| In the menu                   | What happens                                                 |
| ----------------------------- | ------------------------------------------------------------ |
| <kbd>SUPER</kbd>+<kbd>R</kbd> | Open your stacks in the menu                                 |
| type                          | Search                                                       |
| <kbd>Enter</kbd>              | Bring the stack up (opening Herdr if needed) — or jump to it |
| ✓                             | This stack is running                                        |
| `＋ New`                      | Name a stack, get a working template in your editor          |

Because stacks are ordinary menu entries, they are searchable from the
Omarchy menu itself: open it anywhere, type the project's name, and press
<kbd>Enter</kbd>.

## The CLI

Everything the menu does is also a command:

```text
rig                           open the stack menu
rig acme                      build acme — or jump to it, if running
rig up acme -b                build in the background
rig kill acme                 close its workspace
rig new widgets --from acme   clone a stack definition into your editor
rig list                      JSON status of every stack, for scripting
rig sync                      put hand-dropped stack files on the menu
```

Every command is idempotent — `rig acme` on a running stack simply takes
you there.

## Stack files

One file per stack in `~/.config/rig/stacks/` — the filename is the stack
name. `root` sets the working directory for every tab and is the only
required key. Every other key is a tab, created in file order:

| A tab like            | Opens                            |
| --------------------- | -------------------------------- |
| `"server": "command"` | One pane, running the command    |
| `"terminal": null`    | One empty terminal               |
| `"workers": { … }`    | One pane per entry, split evenly |

After a build, focus lands on the last tab in the file — end with
`"terminal": null` to start in an empty shell.

### Waiting on other panes

Some panes shouldn't start until something else is ready. Declare that
with the long pane form:

```json
{
  "root": "~/Projects/widgets",
  "server": {
    "sail": "./vendor/bin/sail up -d",
    "vite": {
      "run": "./vendor/bin/sail npm run build",
      "after": "sail"
    },
    "tunnel": {
      "run": "cloudflared tunnel run widgets-dev",
      "after": "vite"
    }
  },
  "workers": {
    "queues": {
      "run": "./vendor/bin/sail artisan queue:work",
      "after": "sail"
    },
    "scheduler": {
      "run": "./vendor/bin/sail artisan schedule:work",
      "after": "sail"
    }
  },
  "terminal": null
}
```

| Key     | Meaning                                                              |
| ------- | -------------------------------------------------------------------- |
| `run`   | The command                                                          |
| `after` | Wait for the named pane — anywhere in the stack — to become ready    |
| `ready` | Optional output pattern, for the rare process that needs precision   |

A pane counts as ready at the first of:

- **its command finishes** — `sail` is ready once the containers are up
- **it starts listening** — a dev server is ready the moment it binds its port
- **its output settles** — a process that neither exits nor listens is
  ready when its output stops
- **two minutes pass** — the gate times out and the pane starts anyway

The wait happens inside the dependent pane, where you can watch it.

## License

Rig is open-source software licensed under the [MIT license](LICENSE).
