@echo off
REM Double-click this to play Dev Souls. No terminal and no Godot editor needed.
REM If anything is wrong it prints why and waits, instead of flashing and vanishing.
setlocal

REM --- this file's folder, WITHOUT the trailing backslash ---
REM %~dp0 ends in "\", and a trailing backslash right before a closing quote escapes that quote, which
REM corrupts the path Godot receives. That was one of the two reasons the old version silently failed.
set "PROJECT=%~dp0"
if "%PROJECT:~-1%"=="\" set "PROJECT=%PROJECT:~0,-1%"

REM --- find the Godot executable winget installed ---
REM Do NOT put a quoted wildcard in a FOR set: cmd can treat it as a literal string, leaving stray quotes
REM in the variable. That was the other reason it failed. `dir /b /s` returns real full paths, one per line.
REM The pattern matches Godot_v4.7.2-stable_win64.exe and NOT ..._win64_console.exe, so the game starts
REM without an extra black console window beside it (verified against the installed files).
set "GODOT="
set "PKGS=%LOCALAPPDATA%\Microsoft\WinGet\Packages"
for /f "usebackq delims=" %%F in (`dir /b /s "%PKGS%\Godot_v*_win64.exe" 2^>nul`) do set "GODOT=%%F"

if not defined GODOT (
    echo.
    echo  Could not find Godot.
    echo.
    echo  Looked in: %PKGS%
    echo  Install it with:   winget install GodotEngine.GodotEngine
    echo.
    pause
    exit /b 1
)

if not exist "%GODOT%" (
    echo.
    echo  Godot was listed but the file is not there:
    echo  %GODOT%
    echo.
    pause
    exit /b 1
)

if not exist "%PROJECT%\project.godot" (
    echo.
    echo  No project.godot found in:
    echo  %PROJECT%
    echo.
    echo  Keep play.bat in the same folder as project.godot.
    echo.
    pause
    exit /b 1
)

REM Launch. This console window closes straight away; the game window takes a few seconds to appear
REM because the 1 km valley builds its terrain, grass and structures on load.
REM No errorlevel check here on purpose: `start` does not report the child's failure reliably, and an
REM earlier version produced a false "failed to start" message because of exactly that.
start "Dev Souls" "%GODOT%" --path "%PROJECT%"
exit /b 0
