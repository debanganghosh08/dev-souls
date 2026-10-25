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
| Export a Windows build (W6) | `"$GODOTC" --headless --export-release "Windows Desktop" builds/DevSouls.exe` |

Notes
- `--headless` has no GPU: it proves code runs, scenes load and logic is correct. It does **not** prove anything
  about how the game looks or its frame rate — only the owner's eyes on a real run can do that. Never claim
  visual or performance results from a headless run.
- A headless run exits non-zero on an uncaught script error, so CI-style checks work.
- First `--import` on a project with assets is CPU-heavy: check load < 50 % and run nothing else alongside it.
