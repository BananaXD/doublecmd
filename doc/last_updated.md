# Last Updated — 2026-07-29

Status log of the Directory Opus-inspired changes. Design doc: `doc/dopus-inspired-usability.md`.

## Done (implemented, compiled OK with `lazbuild --ws=qt5 src/doublecmd.lpi`)

1. **Multi-mode find-as-you-type bar** — `src/frames/fquicksearch.pas`
   - First typed character picks the mode, bold label on the left shows it:
     - no prefix → normal quick search (unchanged)
     - `*` → live filter mode (prefix stripped from the pattern, deleting `*` switches back).
       FIXED 2026-07-25: typing `*` never *opened* the bar — `CheckSearchOrFilter(UTF8Key)`
       discarded `+`/`-`/`*` chars (numpad-selection-key guard), so the mode was unreachable
       from the panel. Now only blocks `*` when the physical Num* key is down
       (`GetKeyState(VK_MULTIPLY)`, LCLIntf), keeping Num* = `cm_MarkInvert` intact while
       main-keyboard `*` (e.g. Shift+8) opens filter mode.
     - `>` → command palette: dropdown listbox above the bar over all `cm_` commands
       (name-prefix matches ranked first, then name/caption substring matches);
       Up/Down navigate, Enter/double-click execute
     - `/` or `~` → go-to-path mode, Enter navigates the active panel
       (goes through `ChooseFileSource`, so archives/URIs work)
   - New event `OnGoToPath`, wired in `src/fileviews/uorderedfileview.pas` (env vars expanded).

2. **Path aliases** — `gPathAliases` in `src/uglobs.pas`, persisted in `doublecmd.xml`
   under `PathAliases/Alias` nodes (Name/Path attributes).
   - `/name` ⏎ jumps to alias target, `/name/sub` appends the rest
   - `/name=/some/path` ⏎ defines an alias, `/name=` ⏎ sets it to the active
     panel's current dir (changed 2026-07-08, was delete), `/name=-` ⏎ deletes it
   - `/=` ⏎ (2026-07-12) saves the current dir as an alias named after its last
     path segment; `/=/some/path` likewise derives the name from the given path
   - Unknown alias = treated as a literal path, so `/home` still works.

3. **Batch inline rename** — `src/fileviews/ufileviewwithmainctrl.pas`
   - If F2 rename starts with 2+ files selected (`FRenBatch`), Enter commits and reopens
     the editor on the next selected file; Esc stops; mouse-click confirm ends the batch.
   - Refactored `edtRenameOnKeySwitch` into `RenameContinueAt` + `NextSelectedFileIndex`.
   - (F2 cycling name/full/ext and Up/Down rename-and-move already existed upstream.)

4. **Shift+E → `cm_SortByDate`** — default hotkey in `src/uglobs.pas` (~line 1214, next to
   the Ctrl+F5 default). Note: shadows starting a quick search with uppercase `E`.

5. New resourcestrings `rsQuickSearchModeCommand` / `rsQuickSearchModeGoTo` in `src/ulng.pas`.

6. **Ctrl+Shift+Alt+A → "name an alias for the current dir" popup** (done 2026-07-03)
   `cm_AddPathAlias` in `src/umaincommands.pas`: `ShowInputQuery` popup pre-filled with the
   last path segment, saves `gPathAliases.Values[name] := path`; filesystem-source only
   (warns otherwise); a typed leading `/` is stripped. Matching `actAddPathAlias` action in
   `src/fmain.pas` + `src/fmain.lfm` (`Tag = 14`, Category `Navigation` — the Tag is
   REQUIRED, the hotkey options page dereferences `Action.Tag`). Default hotkey
   `Ctrl+Shift+Alt+A` in uglobs.pas; also reachable via `>AddPathAlias` in the palette.

7. **Right-click "Open in terminal"** (done 2026-07-03) — `src/platform/unix/ushellcontextmenu.pas`
   New `OpenInTerminalSelect` handler using `ProcessExtCommandFork(gRunTermCmd,
   gRunTermParams, path)` (same as `cm_RunTerm`). Shown for directory items (opens that
   folder, before "Pack here...") and on the panel-background menu after "Refresh" (opens
   the current dir). Filesystem source only. Strings `rsMnuOpenInTerminal`,
   `rsMsgTitleAddPathAlias`, `rsMsgPromptAddPathAlias` added to uLng.

8. **Explicit hotkeys beat find-as-you-type** (2026-07-03) — `src/uhotkeymanager.pas`
   `KeyDownHandler` used to suppress ALL letter-key hotkeys whose modifier combo maps to a
   key-typing action (Shift is a "text" modifier, so plain/Shift letters = quick search and
   Ctrl+Alt[+Shift] letters = quick filter — this silently killed both Shift+E and
   Ctrl+Shift+Alt+A). Added `HasExplicitHotkey`: if the pressed shortcut is actually bound
   (control- or form-level), the hotkey fires instead of typing into the search bar.
   Trade-off: a bound letter combo can no longer start find-as-you-type with that letter.

9. **Go-to mode autofill** (2026-07-03) — `src/frames/fquicksearch.pas`
   Typing `/` now shows the alias list in the same dropdown used by `>` command mode
   (`/name  -  target` rows, prefix matches first). Up/Down/click select, Enter navigates.
   Precedence on Enter: an arrow/mouse-picked entry always wins; otherwise exact alias or
   existing literal path beats the top suggestion. List hides once a subpath (`/name/...`)
   or an `=` definition is being typed. Shared plumbing: `FDropdownValues` holds the value
   behind each visible row (command name / target path), `ShowDropdown` does sizing.
   - EXTENDED 2026-07-29: **subdirectory completion** (`UpdateDirectoryList`). Once the
     typed text goes past the first `/segment` — or is a `~/`, `C:`/`C:\`, or `\` drive
     form — the dropdown lists real subdirectories of the base directory (text up to the
     last separator, alias-expanded via `ResolveGoToPath`; on Windows a bare leading
     separator is resolved against the active panel's drive, mirroring
     `quickSearchGoToPath`). Rows show the full target path; name-prefix matches ranked
     first, then substring matches; enumeration via `uFindEx`/`FPS_ISDIR`. Enter
     precedence in `DoGoToPath` changed from `(Path = S) and not mbDirectoryExists(S)`
     to `not mbDirectoryExists(Path)` — otherwise an alias+partial like `/cc/dou`
     resolved to a nonexistent path and the highlighted suggestion was ignored.

10. **Windows parity** (2026-07-03, NOT compile-tested — no cross-compiler on this machine;
    verify on a Windows build):
    - "Open in terminal" added to `src/platform/win/ushellcontextmenu.pas`: background menu
      entry (after Refresh) runs `cm_RunTerm`; directory items get an entry executing
      `gRunTermCmd`/`gRunTermParams` with the clicked folder as start path via the existing
      `TExtActionCommand`/`USER_CMD_ID` mechanism.
    - Go-to mode on Windows (`{$IFDEF MSWINDOWS}` in fquicksearch.pas + uorderedfileview.pas):
      `\path` and no-alias `/path` resolve against the active panel's drive (fallback `C:`),
      UNC `\\server` left alone; `C:`/`C:\path` (any drive letter + colon) enters go-to mode
      and navigates literally; `/alias\sub` splits on both separators (`PATH_SEPARATORS`).

11. **Ctrl+U → copy to other panel** (2026-07-10) — default hotkey in `src/uglobs.pas`,
    "Main" context: `Ctrl+U` now runs `cm_Copy` (was `cm_Exchange`, which is now unbound).
    hkVersion bumped to 73 with a migration that rebinds existing profiles.

12. **Ctrl+Left / Ctrl+Right nudge the panel splitter** (2026-07-10)
    - `cm_PanelsSplitterPerPos` (`src/umaincommands.pas`) now accepts a signed
      `splitpct` (`+5`/`-5`) meaning relative to the current position, clamped 0–100;
      unsigned values stay absolute.
    - Default hotkeys in "Files Panel" context: `Ctrl+Left` = `splitpct=-5`,
      `Ctrl+Right` = `splitpct=+5` (were `cm_TransferLeft`/`cm_TransferRight`,
      now unbound; hkVersion 73 migration rebinds existing profiles).

13. **Ctrl+PgUp / Ctrl+PgDn switch tabs, Chrome-style** (2026-07-12) — "Main" context
    defaults in `src/uglobs.pas` now bind them to `cm_PrevTab`/`cm_NextTab` alongside
    Ctrl+Shift+Tab/Ctrl+Tab (single AddIfNotExists call per command with the existing
    shortcut passed as OldShortcuts, else the add is skipped — see item 12's fix).
    Previously `cm_ChangeDirToParent`/`cm_OpenArchive`, now unbound; hkVersion 75
    migration rebinds existing profiles.

14. **Flat view promotion, DOpus-style** (2026-07-26) — design-doc item 4.
    Core flat view already existed (`cm_FlatView`, Ctrl+B); this makes it first-class:
    - Default hotkeys (hkVersion 77): **Ctrl+B = `cm_FlatView dirs=off`**
      (files-only flat) and **Ctrl+Alt+F = `cm_FlatView dirs=on`** (flat with
      directory rows, DOpus "Mixed"). Each key enters/switches to its mode and
      exits flat view when pressed again in that same mode; migration removes
      old parameterless bindings first (AddIfNotExists skips existing shortcuts,
      item-12 lesson). To make Ctrl+Alt+F fire at all, the Windows AltGr
      suppression in `uhotkeymanager.pas` `KeyDownHandler` now consults
      `HasExplicitHotkey` (explicitly bound Ctrl+Alt combos beat typing).
    - **`cm_FlatView dirs=on|off|toggle`** — parameterized mode selection. New
      `FlatViewDirs` plumbed `TFileView` → `TFileListBuilder`
      → `TFileSourceListOperation`; only the filesystem list op honors it (WCX
      archives stay files-only). Enter/double-click on a dir row exits flat view
      and lands in that dir (`ChangePathToChild` flat branch uses `aFile.FullPath`;
      `SetCurrentPath` clears the flag). Parameterless `cm_FlatView` (menu item)
      keeps the old behavior: enter files-only flat / exit from any flat mode.
    - **`TFileView.ExitFlatView`** — extracted exit logic (navigate to active
      file's real dir, or pop the search-result source for `cm_FlatViewSel`);
      used by `cm_FlatView`, `cm_FlatViewSel`, and a new **Esc exits flat view**
      branch in `uorderedfileview.pas` (progressive: search bar → filter →
      cancel work → exit flat).
    - **Auto "Location" column** (columns view only): entering flat view installs
      a temporary slave columns class (`isSlave`/`ActiveColmSlave`, same mechanism
      as fFindDlg feed-to-panel) — a clone of the active set plus a synthetic
      `Location` column at index 1 with content `[DC().GETFILEPATH{}]` (so header
      sorting maps to `fsfPath`), rendered as the path *relative to the flat root*
      via an override in `MakeColumnsStrings`. Removed on exit; user's real column
      set never touched. `DoColumnResized` now skips width persistence for slave
      sets (also fixes latent width-corruption via fFindDlg slave tabs).
      New members `FFlatColumnsSet`/`FFlatLocationCol`/`EnsureFlatViewColumns`
      (called from `BeforeMakeFileList` + `DisplayFileListChanged`).
    - **FLAT badge**: `TPathLabel` got a `Prefix` property drawn inverted before
      the path (`TextIndent` keeps segment-click hit-testing aligned);
      `TFileViewHeader.UpdatePathLabel` sets it from `FlatView`;
      `TFileViewWithPanels.DisplayFileListChanged` refreshes the label.
      `actFlatView.Checked` tracked in `fmain.pas` (`UpdateFileView` +
      `FileViewFilesChanged`). Strings `rsColLocation`, `rsFlatViewIndicator`.
    - Not done (user deferred): live recursive FS watching on Windows,
      path-aware quick filter. Flat state is not session-persisted (upstream
      behavior, unchanged).

Build note: if FPC dies with a random internal `EListError` in unmodified units,
run `./clean.sh && ./build.sh components` then rebuild — stale PPU state.
On Windows: `clean.bat` + `build.bat components`, then
`C:\lazarus\lazbuild.exe src\doublecmd.lpi --bm=release` (rename a running
`doublecmd.exe` to `doublecmd.exe.old` first, or linking fails with error 5).

## Dropped

- `>cmd` terminal command in the palette — `>RunTerm` (existing `cm_RunTerm`) already
  covers it; user is fine with that.

## Not done from design-doc item 5

- Rename undo (Ctrl+Z) and inline wildcard pattern rename.
