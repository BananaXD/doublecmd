# doublecmd default hotkeys — HANDOFF

Updated: 2026-10-12

## Goal

Make the fork's preferred key bindings ship as defaults, so anyone pulling
`banana/master` gets them on first start, and existing profiles are migrated.

## Stage

Done, verified, pushed. F7, F8 and Shift+F8 all run `cm_MakeDir`; the bottom
function-key bar's F8 button is MkDir too. Delete is Del / Shift+Del only.
Shift+E → `cm_SortByDate` was already a default (since commit 32f679dbd).

## Changed

- `src/uglobs.pas:176` — `hkVersion` 78 → 80 with changelog comments (79, 80).
- `src/uglobs.pas` `LoadDefaultHotkeyBindings` (~line 1190): `< 80` migration
  removes `F8`/`Shift+F8 → cm_Delete` and the interim v79 `F8 → cm_MakeDir`;
  `cm_MakeDir` added as F7/F8/Shift+F8 with `OldShortcuts=['F7']`.
- `src/fmain.lfm` `btnF8`: `Action = actMakeDir`, caption "Directory", no
  click/mousedown handlers. `src/fmain.pas`: `btnF8Click` and
  `btnF8MouseDown` (trash context menu on right-click) deleted.
- `doc/last_updated.md` — item 18.

## Decisions

- Migration via hkVersion, not just a new default: `AddIfNotExists` never
  overrides an existing binding, and its `OldShortcuts` overload only adds
  when every existing entry for the command equals the old set. So the
  migration strips F8 from `cm_MakeDir` too before re-adding F7/F8/Shift+F8.
- Right-click trash context menu on the F8 bar button dropped with the
  button's delete role; still reachable elsewhere (trash can in drive bar).

## Open / Next

- Nothing pending for this effort.

## Gotchas

- Verify migrations without touching the live profile: copy
  `%APPDATA%\doublecmd\shortcuts.scf` into a temp dir and run
  `doublecmd.exe --no-splash --config-dir=<tmp> -L C:\ -R C:\`, close with
  `CloseMainWindow()`, then inspect the saved `shortcuts.scf` (Version attr).
- Every build this session hit the stale-PPU `EListError` flake on first try;
  `clean.bat` + `build.bat components` + lazbuild fixed it (~35 s). A running
  instance locks `doublecmd.exe.old`, so rename to a fresh name (`.old2`).
- `C:\cc\cc-docs\sync.ps1` aborts on git's CRLF warning (PowerShell treats
  stderr as an error) and leaves the file staged; commit/push in cc-docs by hand.
