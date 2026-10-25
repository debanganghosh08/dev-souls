@echo off
REM Double-click this to play Dev Souls. Finds Godot where winget installed it.
setlocal
set GODOT_DIR=%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe
for %%F in ("%GODOT_DIR%\Godot_v*_win64.exe") do set GODOT=%%F
if not defined GODOT (
  echo Could not find Godot. Install it with:  winget install GodotEngine.GodotEngine
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0"
endlocal
