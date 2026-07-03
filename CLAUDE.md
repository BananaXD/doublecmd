# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Double Commander — a cross-platform dual-panel file manager written in Free Pascal (Object Pascal) with Lazarus/LCL. This clone: `origin` = the user's fork (BananaXD/doublecmd), `upstream` = official doublecmd/doublecmd. Ongoing feature work (Directory Opus-inspired usability) is documented in `doc/dopus-inspired-usability.md` (design) and `doc/last_updated.md` (status log) — read the status log before continuing that work.

## Build

```sh
./build.sh components                  # build component packages (needed once, and after ./clean.sh)
lazbuild --ws=qt5 src/doublecmd.lpi    # build the app (this machine uses the qt5 widgetset)
```

Binary lands at repo root: `./doublecmd`. Full builds: `./build.sh debug|release|plugins`. `./clean.sh` removes all build output.

- **Known flake:** incremental builds sometimes die with an FPC-internal `EListError: List index exceeds bounds` in *unmodified* units. This is stale PPU state, not your change — run `./clean.sh && ./build.sh components` and rebuild.
- There is no test suite. Verify by building and running the app.
- Success looks like `... lines compiled` with no `Error:` lines; `Error: File "dmhigh.json" not found.` during the components build is pre-existing noise.
- Windows/macOS code paths cannot be compiled on this Linux machine (no cross-compiler) — flag Windows-only changes as not compile-tested.

## Architecture

### Commands system (how every feature is exposed)
User-facing actions are `cm_*` commands. `uformcommands.pas` discovers them via RTTI: any **published** `procedure cm_Foo(const Params: array of string)` on a registered class becomes a command. `TMainCommands` (`src/umaincommands.pas`) holds main-form commands, including thin delegators to the active file view (which publish their own `cm_` methods, e.g. in `uorderedfileview.pas`). Execute programmatically via `frmMain.Commands.Commands.ExecuteCommand('cm_Foo', [])`.

**Adding a command to TMainCommands requires a matching `TAction`** named `actFoo` in `src/fmain.pas` (field) and `src/fmain.lfm` (object in `actionLst` with `Tag`, `Category`, `Caption`, `OnExecute = actExecute`). The `Tag` is mandatory — it indexes the category list `rsCmdCategoryListInOrder` in `uLng`, and the hotkey options page dereferences `Action.Tag` without a nil check (a command without an action crashes that dialog).

### File views and file sources
- View class hierarchy in `src/fileviews/`: `ufileview.pas` (base `TFileView`) → `ufileviewwithpanels` → `ufileviewwithmainctrl` (mouse/keyboard/drag-drop/inline rename) → `uorderedfileview` (quick search bar, selection) → concrete views `ucolumnsfileview`, `ubrieffileview`, `uthumbfileview`. Views live as tabs in `TFileViewNotebook` (`ufileviewnotebook.pas`).
- Everything a panel displays comes through an `IFileSource` (`src/filesources/`): filesystem, archives (WCX), network (WFX), search results, flat view. Navigate with `uFileSourceUtil.ChooseFileSource(FileView, Path)` — it parses URIs/archives, so features built on it work inside archives and remote FS for free.
- Long-running work (copy/move/calc statistics) are `TFileSourceOperation` objects run by `TOperationsManager` (`src/uoperationsmanager.pas`, queues) with UI in `src/fFileOpDlg.pas`. Per-view background work (icons, properties) goes through `ufileviewworker.pas`.

### Quick search bar (find-as-you-type)
`src/frames/fquicksearch.pas` — one frame per file view (created/wired in `uorderedfileview.pas`). Multi-mode by first typed character: plain = search, `*` = filter, `>` = command palette, `/`/`~` (+ Windows drive/`\` forms) = go-to path with alias autofill. Path aliases live in `gPathAliases` (uglobs, persisted in doublecmd.xml under `PathAliases`).

### Hotkeys
`uhotkeymanager.pas` (`HotMan`). Defaults are added in `uglobs.pas` `LoadDefaultHotkeyBindings` via `AddIfNotExists([...],[],'cm_Foo')` (runs every startup; won't override user bindings). `KeyDownHandler` arbitrates hotkeys vs. find-as-you-type on letter keys: modifier combos that map to typing actions (`gKeyTyping`; Shift is a "text" modifier and masked out) suppress letter hotkeys **unless the exact shortcut is explicitly bound** (`HasExplicitHotkey`). User hotkeys persist in `shortcuts.scf`.

### Configuration and strings
- `src/uglobs.pas` — all global settings (`g*` variables), created in `CreateGlobs`, loaded/saved in `LoadXmlConfig`/`SaveXmlConfig` (doublecmd.xml via `gConfig: TXmlConfig`); histories go to history.xml.
- Every UI string is a `resourcestring` in `src/ulng.pas` (`rs*`) — never hardcode UI text.

### Platform split
`src/platform/{unix,win,darwin}` contain same-named units resolved by search path — e.g. there are **two** `ushellcontextmenu.pas`: unix builds its own `TPopupMenu`; win wraps the native `IContextMenu`/`HMENU` and injects custom entries with IDs ≥ `USER_CMD_ID` dispatched through `TExtActionCommand` (command name executed via `ProcessExtCommandFork` or `IFormCommands`). Platform-specific code in shared units uses `{$IFDEF MSWINDOWS}`/`{$IF DEFINED(...)}`.

### Forms
`.lfm` files are plain text and edited by hand (no Lazarus IDE here); every component in an `.lfm` needs a matching field declaration in the form class in the `.pas`. `src/fmain.pas`/`fmain.lfm` is the (very large) main form owning both panels, toolbars, and the action list.

## Conventions

- Commit messages use the upstream `ADD:`/`FIX:` prefix style.
- Reusable UI components live in `components/` (e.g. KASToolBar) as Lazarus packages; plugin APIs (WCX/WDX/WFX/WLX) and bundled plugins in `plugins/` and `sdk/`.
