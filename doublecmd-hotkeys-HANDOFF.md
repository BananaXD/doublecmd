# doublecmd default hotkeys — HANDOFF

Updated: 2026-10-12

## Goal

Make the fork's preferred key bindings ship as defaults, so anyone pulling
`banana/master` gets them on first start, and existing profiles are migrated.

## Stage

Done and verified. F8 → `cm_MakeDir` (alongside F7), Shift+F8/Del still delete.
Shift+E → `cm_SortByDate` was already a default (since commit 32f679dbd).

## Changed

- `src/uglobs.pas:176` — `hkVersion` 78 → 79 with changelog comment.
- `src/uglobs.pas` `LoadDefaultHotkeyBindings` (~line 1190): `< 79` migration
  removes a parameterless `F8 → cm_Delete`; `cm_MakeDir` now added as
  `['F7','','','F8','','']` with `OldShortcuts=['F7']`; `cm_Delete` default is
  only `Shift+F8 trashcan=reversesetting` (plus Del/Shift+Del further down).
- `doc/last_updated.md` — item 18.

## Decisions

- Migration via hkVersion, not just a new default: `AddIfNotExists` never
  overrides an existing binding, so without removing F8 from `cm_Delete`
  existing users would never get F8 = MkDir.
- The bottom function-key bar button `btnF8` (`src/fmain.pas:1407`) still
  deletes and reads "Delete". Left as is; only the key was requested.

## Open / Next

- Decide whether `btnF8` should also become MkDir (caption in `src/fmain.lfm:1018`).

## Gotchas

- Verify migrations without touching the live profile: copy
  `%APPDATA%\doublecmd\shortcuts.scf` into a temp dir and run
  `doublecmd.exe --no-splash --config-dir=<tmp> -L C:\ -R C:\`, close with
  `CloseMainWindow()`, then inspect the saved `shortcuts.scf` (Version attr).
- First build after the edit hit the stale-PPU `EListError` flake; `clean.bat`
  + `build.bat components` + lazbuild fixed it (see memory windows-build-setup).
