# Tool paths and commands (Windows, this machine)

## Just playing it (owner)
- **Double-click `play.bat`** in the project root — finds Godot and runs the game. Nothing else needed.
- To tune values live, double-click **`project.godot`** to open the editor, then press **▶ Play** (F5).
- Controls: WASD move · mouse look · Shift sprint · Space dodge · E interact · LMB/RMB light/heavy attack ·
  Tab inventory · Esc pause · F3 debug readout. Title screen → **New Journey**.
- **If models are missing** (errors about `res://assets/...` not found), the git-ignored art is absent or
  incomplete: run `node tools/fetch-assets.mjs` to restore it from the tracked manifest (~267 MB), then
  `--headless --import` once.

Godot **4.7.2 stable** (standard build) installed 2026-10-23 with `winget install GodotEngine.GodotEngine`.
It is NOT on PATH for non-interactive shells, so always use the full path. Use the **console** build for
anything headless (the plain `.exe` writes nothing to stdout).

```
GODOT_DIR = C:/Users/primu/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe
GODOT     = $GODOT_DIR/Godot_v4.7.2-stable_win64.exe              # editor / playing the game
GODOTC    = $GODOT_DIR/Godot_v4.7.2-stable_win64_console.exe      # headless, prints to stdout
```

Run from the project root (`C:/Projects/porty/dev-souls`):

| Purpose | Command |
|---|---|
| Version check | `"$GODOTC" --version` |
| Import assets / build the `.godot` cache (first run, or after new files) | `"$GODOTC" --headless --import` |
| Run the test suite | `"$GODOTC" --headless --script tests/run_tests.gd` |
| Open the editor | `"$GODOT" --editor` (owner only — do not leave running) |
| Play the game | `"$GODOT"` (owner only) |
| Export a Windows build | `"$GODOTC" --headless --export-release "Windows Desktop"` |
| Check an exported build boots and its pack is complete | `cd builds/windows && ./DevSouls.exe --headless --quit-after 1200 -- --probe` |

Notes
- `--headless` has no GPU: it proves code runs, scenes load and logic is correct. It does **not** prove anything
  about how the game looks or its frame rate — only the owner's eyes on a real run can do that. Never claim
  visual or performance results from a headless run.
- A headless run exits non-zero on an uncaught script error, so CI-style checks work.
- **Always check the suite output for `SCRIPT ERROR` too, not just `PASS n / FAIL 0`.** A GDScript runtime
  error aborts the function it happens in and raises nothing the runner can catch, so a test that dies
  part-way still reports as passed. `run_tests.gd` now fails any test that reached no assertion, which
  catches an error before the first one; grepping the output for `SCRIPT ERROR` (expected: 0 in a checkout
  that has `assets/`) catches the rest.
- First `--import` on a project with assets is CPU-heavy: check load < 50 % and run nothing else alongside it.

## Shipping a Windows build

Proven working on 2026-10-26: `DevSouls.exe` 104 MB + `DevSouls.pck` 422 MB, **526 MB total**, which is the
download a player gets. The two files must stay side by side; the `.exe` finds the `.pck` by name beside it.

**One-time setup, already done on this machine.** The export needs Godot's Windows templates, which the
editor downloads but the CLI does not. They are not in the repo and never should be (D-005). Get them with:

```
curl -L -o templates.tpz \
  https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz
```

That archive is **1.19 GB** (1,281,349,702 bytes exactly) and holds every platform. Only four files are
needed, so extract those rather than the lot, into
`%APPDATA%/Godot/export_templates/4.7.2.stable/` — `windows_{debug,release}_x86_64.exe`, the two matching
`_console.exe`, and `version.txt` (whose contents must equal the folder name or Godot ignores the folder).
Then delete the archive. Kept: 212 MB.

**What is in the build.** `export_presets.cfg` uses `export_filter="all_resources"`, so everything under
`res://` is packed **including the git-ignored `assets/` tree** — `.gitignore` has no bearing on an export.
`exclude_filter` drops `docs/`, `tests/`, `tools/` and the six test scenes; nothing shipped references them
(checked). Verified by running the exported build's own `--probe`: all seven PROBE lines printed with no
error, which means the vale, the castle, the village, the trees, the grass and the player model all loaded
out of the pack.

**Not verified by any of this:** how it looks, how it runs, or whether it works on a machine that is not
this one. A headless probe opens no window and renders nothing. Before release it needs a real run on the
owner's machine, and ideally one on a PC that has never had Godot installed.
