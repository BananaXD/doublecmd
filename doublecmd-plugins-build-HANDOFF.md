# doublecmd plugins build — HANDOFF

Updated: 2026-09-19

## Goal
Get the bundled archiver/content/lister plugins (`*.wcx/*.wdx/*.wfx/*.wlx`) built for the
local Windows build of Double Commander, so opening `.zip`/`.7z`/`.rar` etc. works.

## Stage
Done. All 13 plugins compiled cleanly (0 `Error:` lines) and sit next to their sources under
`plugins\`. `zip.wcx` exists at `plugins\wcx\zip\zip.wcx`, which is the path DC's plugin
config resolves `%commander_path%\plugins\wcx\zip\zip.wcx` to.

## Changed
- No source files. Build output only (untracked binaries under `plugins\**`).

## Decisions
- Used the repo's own `build.bat plugins` (→ `plugins\build.bat`) instead of building each `.lpi`
  by hand — it walks every plugin in the right order.

## Open / Next
- Restart Double Commander and open a `.zip`; the "Cannot load WCX module" dialog should be gone.
- If it still fails after restart: Options → Plugins → WCX — check the zip entry is enabled and
  points at the file above.

## Gotchas
- `build.bat` expects `LAZARUS_HOME` (defaults to a bogus `D:\...` path). Set
  `$env:LAZARUS_HOME='C:\lazarus'` and prepend `C:\lazarus` to `PATH` first.
- Invoke it by **full path** (`cmd.exe /c C:\cc\doublecmd\build.bat plugins`). `cmd /c "cd /d ... && build.bat"`
  from the sandboxed PowerShell fails with `'build.bat' is not recognized` — cwd is not honoured there.
- Piping cmd output through `2>&1 | Select-String` inside the sandbox swallowed everything and returned
  exit 1 with no text. Redirect to a log file with `*> $log` and grep the file instead.
- Reusable one-shot:
  ```powershell
  $env:LAZARUS_HOME='C:\lazarus'; $env:PATH="C:\lazarus;$env:PATH"
  & cmd.exe /c "C:\cc\doublecmd\build.bat plugins" *> "$env:TEMP\dc-plugins-build.log"
  Select-String "$env:TEMP\dc-plugins-build.log" -Pattern 'Error:|Fatal:'
  ```
