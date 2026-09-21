# Omarchy cheat sheet

Hold **SUPER** and a keybinding cheat sheet fades in. Let go and it's gone.

![The cheat sheet overlay](docs/cheatsheet.png)

The sheet is generated from your live bindings, not from a list someone typed
out. Rebind a key and the chip follows it; unbind one and its row disappears.
SUPER itself never gets a chip — you're holding it — so only the extras are
drawn: `Ctrl`, `Alt` and `⇧`.

## Requirements

- Omarchy 4 (Quickshell-based `omarchy-shell`)
- Hyprland 0.56.2 or newer

## Install

```bash
omarchy plugin add https://github.com/titteerbot/omarchy-cheatsheet.git
omarchy plugin enable titteerbot.cheatsheet
omarchy restart shell
```

Then load the plugin's Hyprland bindings from `~/.config/hypr/bindings.lua`.
The plugin cannot do this for you, and without it nothing will appear:

```lua
local cheatsheet = os.getenv("HOME") .. "/.config/omarchy/plugins/titteerbot.cheatsheet/hypr/cheatsheet.lua"
local cheatsheet_file = io.open(cheatsheet)
if cheatsheet_file then
  cheatsheet_file:close()
  dofile(cheatsheet)
end
```

Reload with `hyprctl reload`, then hold SUPER.

The binding logic lives in the plugin's `hypr/cheatsheet.lua`, so
`omarchy plugin update` keeps it current. The existence check is not
optional: without it, a bare `dofile` raises `cannot open …` once the plugin is
removed, and that breaks loading Hyprland's config entirely.

## How it works

All of this was measured against Hyprland 0.56.2 rather than assumed.

- **`non_consuming` on the press bind.** Without it the bind swallows SUPER and
  it stops working as a modifier — the sheet would advertise chords it had just
  broken.
- **`global`, not `exec`.** Every chord you type starts with SUPER, so an exec
  bind here would spawn two processes (~55 ms) on every single shortcut. The
  `global` dispatcher hands the event straight to the already-running shell over
  `hyprland-global-shortcuts`, with no process at all.
- **A key poll, not a release bind.** The obvious design — a second bind that
  fires on SUPER's release — fails in practice: Hyprland suppresses a release
  bind once any chord has fired during the same hold. And many chords
  (`SUPER+C`, `SUPER+V`, the menus) emit no compositor event the shell could
  watch for instead. So the press bind asks the compositor directly: it polls
  `hl.is_key_down("Super_L")` every 50 ms inside Hyprland's own Lua runtime, and
  raises `cheatsheet:unhold` the moment SUPER physically comes up. Nothing is
  spawned, and the poll only runs while SUPER is held.
- **`"Super_L"`, exactly.** `is_key_down` takes an xkb keysym name, and casing
  matters: `"SUPER_L"` and `"SUPER"` silently return `nil`.
- **Two shortcuts, not one.** `global` delivers one edge per bind — a press
  bind raises `pressed` and never `released` — so dismissal is its own shortcut.

## Behaviour

- **Tap-proof.** The sheet only appears after SUPER has been held for 200 ms, so
  ordinary chords like `SUPER+W` never flash it, however fast you type them.
- **Never takes the keyboard.** The layer surface is `WlrKeyboardFocus.None`
  with an empty input region, so it cannot eat the chord it is advertising and
  clicks fall through to the windows underneath.
- **Gone when SUPER is.** The key poll closes the sheet on release after every
  chord. Chords with a visible effect (closing, floating or opening a window,
  switching workspace) close it the moment they land, before you let go.

## Configuration

Knobs live at the top of `Cheatsheet.qml`:

| Property | Default | What it does |
|---|---|---|
| `revealDelay` | `200` | ms SUPER must be held before the sheet appears |
| `maxVisibleMs` | `20000` | last-resort cap; matches `MAX_TICKS` in `hypr/cheatsheet.lua` |
| `chipsWidth` | `Style.space(62)` | width of the keycap column |
| `columnGap` | `Style.space(22)` | space between sections |

Which bindings appear, and how they're grouped, is the `SECTIONS` table in
`CheatsheetModel.js`. Each row is either a `desc` that's looked up in your live
bindings, or a hand-drawn `keys` summary that collapses a family (the arrow
keys, workspaces 1–9) into one line and names a `requires` description so it
disappears if you unbind that family.

### Adding your own rows

To put your own bindings on the sheet without editing the plugin, add
`sections` to its entry in `~/.config/omarchy/shell.json`. Rows take the same
two shapes as the built-in table:

```json
"plugins": [
  {
    "id": "titteerbot.cheatsheet",
    "sections": [
      {
        "title": "Launch",
        "rows": [
          { "desc": "Windows desktop (RDP)", "label": "Windows desktop" }
        ]
      },
      {
        "title": "Media",
        "rows": [
          { "desc": "Play/pause" },
          { "keys": ["F7", "–", "F9"], "label": "Media keys", "requires": "Play/pause" }
        ]
      }
    ]
  }
]
```

- A section whose `title` matches a built-in one (ignoring case) gets its rows
  added to the end of it. Any other title becomes a new section after the
  built-ins.
- `desc` is the description you gave the binding, e.g. the second argument to
  `o.bind(...)`. Run `hyprctl binds -j` to see them. As with the built-in
  rows, a row whose binding doesn't exist is left off.
- Malformed rows are skipped, and a `shell.json` that doesn't parse leaves
  just the built-in sheet.
- The file is watched, so changes show up on the next hold without a restart.
  These rows live outside the plugin directory, so `omarchy plugin update`
  leaves them alone.

Saving a change to the QML needs `omarchy restart shell`: the plugin is
`keepLoaded`, and Omarchy's hot-reload does not replace a kept instance.
Changes to `hypr/cheatsheet.lua` need `hyprctl reload` instead.

## Known limitations

- **Workspace rows are hand-labelled.** Hyprland reports Lua `code:NN` bindings
  with an empty `key` *and* `keycode: 0`, so there is nothing to resolve. The
  `1–9` chips are drawn from the curation table instead of from your bindings.
- **Multi-monitor is untested.** The overlay follows `Hyprland.focusedMonitor`,
  but it has only ever run on a single-output machine.

## Licence

GPL-3.0 — see [LICENSE](LICENSE).
