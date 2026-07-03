# Making Double Commander Feel More Like Directory Opus

**Scope:** This document proposes changes to Double Commander's *day-to-day interaction model* —
what happens when you type, click, rename, copy, and navigate — inspired by Directory Opus (DOpus).
It deliberately avoids "add more options" proposals; every item here changes the default, basic
experience of using the program. Each item describes what DOpus does, what Double Commander (DC)
does today (with pointers into this source tree), and a concrete implementation direction.

This is the first batch of 10. More to follow.

---

## 1. Turn the type-to-search bar into a multi-mode "Find-As-You-Type" field

**What DOpus does:** Typing in a file display opens the FAYT field at the bottom of the lister.
Plain typing jumps to matching files, but a *prefix character* switches the same field into a
different mode without any dialog:

| Prefix | Mode |
|--------|------|
| (none) | Find/jump to file, with recursive fuzzy option |
| `*` | Filter the file display to matching items |
| `>` | Run an internal command by name (a command palette) |
| `/` or `:` | Type/paste a path and jump to it, with autocomplete |
| `?` | Fuzzy/keyword search of the current folder |

One muscle-memory entry point ("just start typing") fans out into search, filter, command
execution, and path navigation.

**What DC does today:** `TfrmQuickSearch` (`src/frames/fquicksearch.pas`) is a docked frame with
an edit box and two hard modes — `qsSearch` (jump/select) and `qsFilter` (hide non-matching) —
chosen by which hotkey/option invoked it. There is no way to switch mode mid-typing, no command
mode, and no path mode. The command palette does not exist at all; commands are only reachable
via menus/hotkeys or the `cm_` names in the configuration dialogs.

**Proposed change:**

1. Keep `TfrmQuickSearch` as the single entry point, but make the first character of the input
   select the mode, DOpus-style:
   - no prefix → current `qsSearch` behavior;
   - `*` → switch live into `qsFilter` (today these are separate activations);
   - `>` → command mode: incremental match against the `cm_` command registry
     (`TfrmMain.Commands` / `uMainCommands.pas` actions list), showing a dropdown of matching
     commands with their localized captions and current hotkeys; Enter executes;
   - `=` or `/` → path mode: the field becomes a path input with directory autocomplete,
     Enter performs `ChooseFileSource`/`SetCurrentPath` on the active view.
2. Show the active mode as a small colored tag on the left edge of the edit (e.g. "FIND",
   "FILTER", "CMD", "GO") so the state is visible.
3. Backspacing past the prefix returns to plain find mode instead of closing the bar.

**Implementation sketch:** All of this lives in `fquicksearch.pas` plus a new dropdown list
control. Command mode needs an enumerable command table — `TFormCommands` already exposes command
names and descriptions for the hotkey option pages (`src/frames/foptionshotkeys.pas` consumes
it), so the palette can reuse that enumeration. Path mode can reuse the completion logic already
used by the `cm_ChangeDir` dialog.

**Why this matters:** This is the single highest-leverage DOpus behavior. It converts a
one-purpose widget into the keyboard hub of the program, and the command palette makes every
`cm_` command discoverable without memorizing hotkeys.

---

## 2. Replace the path label with a real breadcrumb bar

**What DOpus does:** The location field renders the path as clickable segments. Each segment
navigates to that ancestor; a `▸` arrow between segments drops down a menu of *sibling folders*
at that level, so you can move sideways through a tree without ever opening it. Clicking the
empty space to the right (or a hotkey) turns the same control into an editable path field with
autocomplete and history dropdown.

**What DC does today:** `TPathLabel` (`src/upathlabel.pas`) is a subclassed `TLabel`. It draws
the path as one string and can highlight the segment under the mouse; clicking a highlighted
segment jumps to that ancestor. That covers ~30% of the DOpus behavior: there are no sibling
dropdowns, and editing the path requires a separate dialog (`cm_ChangeDir`).

**Proposed change:** Promote `TPathLabel` into a `TBreadcrumbBar` composite:

1. Render each path segment as its own hot-tracked region with a `▸` separator (keep the flat
   label look; no need for button chrome).
2. Clicking a `▸` separator enumerates the sibling directories of the segment to its left via the
   file source (`FileSource.CreateListOperation`) and shows them in a popup menu; selecting one
   navigates there. This must go through the file-source API, not raw `FindFirst`, so it works
   inside archives and on network/WFX file systems too.
3. Click on the empty area right of the last segment (or `Ctrl+L` / current `cm_ChangeDir`
   hotkey) swaps the breadcrumb for an inline `TEdit` with directory autocomplete, pre-filled
   with the current path and fully selected. `Esc` restores the breadcrumb.
4. When the path is longer than the control, collapse leading segments into a `«` overflow
   dropdown instead of clipping text.

**Implementation sketch:** `upathlabel.pas` already tracks per-segment hit rectangles for its
highlight feature, so the geometry work is largely done; the additions are the separator hit
zones, the popup, and the edit-swap. The container that hosts the path label is created in
`TfrmMain` (`src/fmain.pas`), which also owns the file view — so wiring navigation is a direct
call to the active `TFileView`.

---

## 3. Show folder sizes automatically in the Size column

**What DOpus does:** Folders can show their real content size directly in the Size column —
calculated in the background as you browse (or instantly via the Everything index on Windows).
Sorting by size then sorts folders by their true size. You never "ask" for a folder size; it is
simply there, and the file display stays responsive while it fills in.

**What DC does today:** Sizes are per-request: `cm_CalculateSpace` / `cm_CountDirContent`
(`src/umaincommands.pas`, ~lines 4125/4155) run a calc-statistics operation
(`src/filesources/ufilesourcecalcstatisticsoperation.pas`) for the selected directories, and the
result is shown until the panel reloads. Spacebar-per-folder is Total-Commander tradition, but it
is manual, transient, and lost on refresh.

**Proposed change:**

1. Add a per-view toggle (default off, one click to enable — e.g. a menu item and a `cm_` command
   `cm_ToggleAutoDirSize`) that, on directory load, enqueues a background calc-statistics
   operation for every directory in the listing, lowest-priority, cancellable on navigation.
2. Stream results into the existing display: `TFileViewWorker`
   (`src/fileviews/ufileviewworker.pas`) already delivers async property updates to file views
   (this is how icons and link resolution arrive), so folder sizes become one more async
   property update rather than a new mechanism.
3. Cache results per (path, mtime) in a session-level dictionary so revisiting a folder is
   instant, and invalidate through the existing file-system watcher notifications.
4. While a size is pending, draw the standard `<DIR>` text; once known, draw the size in the same
   formatting the column set specifies for files. Sorting by size treats known folder sizes as
   values and pending ones as -1 (sorted together at the end).

**Why this matters:** "Where did my disk space go" is one of the most common file-manager tasks,
and DOpus answers it passively. The operation and threading infrastructure already exist in DC;
this is mostly orchestration plus caching.

---

## 4. Make Flat View a first-class, one-keystroke mode

**What DOpus does:** Flat View is a toggle on the folder itself: press it and the file display
shows *all files in all subfolders* as one list, in two flavors — **Mixed** (a flat soup of
files, with a Location column) and **Grouped** (files still indented under their subfolder
headings, like an expanded tree). Toggle again and you're back. It respects the current filter,
updates live, and operations (delete, rename, copy) work on the flattened items directly.

**What DC does today:** The machinery exists but is buried: `TFlatViewFileSource`
(`src/filesources/uflatviewfilesource.pas`) extends the search-result file source and presents a
flattened listing (`cm_FlatView` exists). But it behaves like landing in a search result: it is a
different file source, the path bar and reload behave oddly, there is no live update, and no
grouped presentation. Most users never find it.

**Proposed change:**

1. Give Flat View a visible affordance: a toolbar toggle button (pressed state while active) and
   show a `FLAT` badge in the path/breadcrumb bar so users always know why the listing looks
   different. `Esc` or navigating up past the flat root exits flat view.
2. Add a **relative Location column** automatically when flat view activates (insert a synthetic
   column showing the path relative to the flat root), and remove it on exit — without requiring
   the user to edit column sets.
3. Live updates: today `TSearchResultFileSource` snapshots its contents. Register the flat root
   with the file-system watcher and re-run the enumeration incrementally (or simply reload) on
   change notifications, so a flat view doesn't silently go stale.
4. (Second phase) Grouped mode: reuse the flat listing but sort by relative path and render
   group header rows per subfolder in `TColumnsFileView` — the grid already supports
   custom-drawn rows.

**Implementation sketch:** Items 1–3 are changes to `uflatviewfilesource.pas`, `fmain.pas`
(badge + toolbar default), and `ucolumnsfileview.pas` (synthetic column). No new file-source
concepts needed.

---

## 5. Upgrade inline rename: field cycling, batch Tab-through, and pattern rename

**What DOpus does:** Inline rename (F2) is a small power tool:

- Repeatedly pressing F2 *cycles the selection* within the edit: name only → name+extension →
  extension only.
- With multiple files selected, finishing a rename with **Tab/Enter moves to the next selected
  file** already in rename mode — you can rename a whole batch inline without a dialog.
- Typing a wildcard pattern (e.g. `*.bak`) into the inline field applies it as a pattern rename
  to the selection.
- `Ctrl+Z` un-renames, even a whole batch.

**What DC does today:** Inline rename exists in `ufileviewwithmainctrl.pas` (`edtRename:
TEditButtonEx`), with commands to select name vs extension and keys to switch between them, plus
`cm_RenameOnly`. It edits exactly one file; batch work means opening the separate Multi-Rename
tool (`src/fmultirename.pas`), which is powerful but modal and heavyweight for "rename these
five files quickly."

**Proposed change:**

1. **F2 cycling:** make repeated `cm_RenameOnly` presses while the editor is open cycle
   name → name.ext → ext, matching DOpus/Explorer muscle memory. The selection-switching code
   already exists; this only adds the cycle state.
2. **Batch inline rename:** when invoked with >1 file selected, committing with Enter renames
   and immediately opens the editor on the next selected file (Shift+Enter for previous, Esc
   stops the run). Show "3 of 7" in the panel status while active.
3. **Undo:** record inline renames on a small per-view undo stack; `Ctrl+Z` in the file view
   reverses the last rename (or the last batch run as one unit). Rename is the safest operation
   to start an undo story with, because the inverse is exact.
4. (Optional, phase 2) If the committed text contains `*` or `?`, interpret it as a pattern
   applied to all selected files — with a one-line preview popup before executing — bridging the
   gap to the full Multi-Rename tool.

**Implementation sketch:** All in `ufileviewwithmainctrl.pas` plus a tiny undo-stack unit. The
actual rename goes through the existing file-source rename/move operation, so archives and WFX
sources inherit the behavior for free.

---

## 6. Navigation Lock: live linked browsing of the two panels

**What DOpus does:** With Navigation Lock enabled, the two file displays move together: enter
`src/` on the left and the right pane enters its own `src/` too; go up on one side, both go up.
DOpus keeps track of the *relative* offset between the two paths, and if one side can't follow
(folder doesn't exist) it tells you and offers to re-sync. This is the killer feature for
comparing two similar trees (a project and its backup, two branches, local vs. remote).

**What DC does today:** Nothing live. `src/fsyncdirsdlg.pas` is a *batch* "Synchronize
Directories" compare/copy dialog — useful, but a different tool. During normal browsing the two
panels are fully independent.

**Proposed change:**

1. New toggle `cm_ToggleNavigationLock` (menu + toolbar + suggested hotkey), enabled per
   panel-pair. When enabled, record the current relative relationship between the two panels'
   paths.
2. Hook directory change on the active view (`TFileView.AfterChangePath` is the natural point —
   `ufileview.pas` already has path-change notification used by tabs and history): compute the
   same relative step (down into `X`, up one, jump to sibling `Y`) and apply it to the passive
   view *without* moving focus.
3. If the passive side lacks the target directory, don't fail silently: flash a non-modal notice
   in the passive panel's status line ("navigation lock: `X` not found — lock suspended") and
   suspend the lock until paths re-align or the user re-toggles.
4. Draw a small chain-link indicator between the two path bars while the lock is active.

**Implementation sketch:** A small coordinator object owned by `TfrmMain` observing both
notebooks. It must ignore path changes it caused itself (re-entrancy guard). File-source
boundaries (archive on one side, FTP on the other) work naturally since navigation goes through
each view's own file source.

---

## 7. Replace the progress dialog with an in-window jobs bar

**What DOpus does:** File copies don't open a dialog that owns your screen. Each job shows as a
compact progress row in a *jobs bar* docked at the bottom of the lister; multiple jobs stack
there. Copies to the same device auto-queue behind each other (parallel writes to one spinning
disk are slower than serial), while jobs to different devices run in parallel. Clicking a row
expands details/pause/abort. An "unattended mode" collects all errors and questions to the end
instead of interrupting mid-copy.

**What DC does today:** The backend is genuinely good: `TOperationsManager`
(`src/uoperationsmanager.pas`) already supports multiple operations, named queues, and moving
operations between queues, and `TfrmFileOp` (`src/fFileOpDlg.pas`) can display a queue. But the
*presentation* is a floating dialog per operation/queue, and queueing is opt-in (F2 or the queue
button when starting an operation). Errors interrupt with modal prompts by default.

**Proposed change (UI re-plumbing, backend mostly stays):**

1. Add a collapsible **jobs panel** at the bottom of `TfrmMain`: one row per
   `TOperationsManagerItem` — icon, source→target summary, thin progress bar, speed, and
   pause/abort buttons. It appears when the first operation starts and folds away when the last
   finishes (with a brief "Copied 1,204 files ✓" toast). Double-click a row to open the existing
   `TfrmFileOp` for full detail — the dialog becomes the drill-down, not the default.
2. **Auto-queue by device:** when a new copy/move starts, derive a device key for the target
   (mount point / drive letter); if an operation with the same key is running, append to that
   queue instead of running parallel. Different device → start immediately. This uses the
   existing queue mechanism; only the assignment policy is new.
3. **Unattended mode:** a checkbox on the copy dialog ("don't interrupt — collect errors") that
   sets the operation's error-handling policy to skip-and-log; at the end, the jobs row turns
   amber and clicking it shows the collected error list with retry options. The operation event
   system already distinguishes question/error states, so this is a policy layer, not a rewrite.

**Why this matters:** This changes the *feel* of the program more than almost anything else:
long copies stop being an interruption and become ambient state, which is exactly how DOpus
users describe the difference.

---

## 8. A viewer pane that doesn't eat the second panel

**What DOpus does:** The viewer pane is a third region of the lister: both file displays stay
visible and usable, and the pane previews whatever file the cursor lands on — images, text,
PDFs, media with playback — instantly and asynchronously, with a small toolbar (rotate, zoom,
full screen).

**What DC does today:** `TQuickViewPanel` (`src/uquickviewpanel.pas`) implements quick view by
**replacing the inactive panel** with an embedded `TfrmViewer`. So using preview costs you dual-
pane operation — you can't compare or copy while previewing. The embedded viewer itself is
capable (`src/fviewer.pas`: text/hex/image/plugins via WLX).

**Proposed change:**

1. Add a third docking slot to the main layout: the quick-view panel can attach to the right
   edge (vertical split) or bottom (horizontal) of the window *in addition to* both file panels,
   with a draggable splitter. Keep the current replace-a-panel behavior as a fallback layout for
   small screens.
2. Preview follows the cursor in the active panel (both panels remain live); debounce cursor
   movement ~150 ms and load the preview on a worker thread so holding an arrow key never
   stutters the file list. `TfrmViewer` currently loads synchronously — the load path needs an
   async wrapper with cancellation when the cursor moves on.
3. Give the pane a micro-toolbar: prev/next image, rotate, zoom-fit toggle, open-in-full-viewer.
4. Show basic metadata under the preview (dimensions, EXIF date, duration, encoding) — the
   viewer already extracts most of this to render at all; it just isn't displayed as fields.

**Implementation sketch:** Layout work in `fmain.pas` (the panel/splitter arrangement is built
there), async load wrapper around `TfrmViewer.LoadFile`, cursor hook via the existing
file-view `OnChangeActiveFile` notification that `TQuickViewPanel` already consumes.

---

## 9. Per-tab history you can see: back/forward with dropdowns, and reopen-closed-tab

**What DOpus does:** Back/Forward behave like a browser: each has a dropdown listing the actual
history entries so you can jump five steps back in one click; long-press opens the list. Every
tab has its own independent history. `Ctrl+Shift+T`-style "undo close tab" reopens the last
closed tab with its history intact, and a "Recently closed tabs" list backs it.

**What DC does today:** Per-view history exists (`src/fileviews/ufileviewhistory.pas`) and
`cm_ViewHistory`/prev/next commands walk it, but it is invisible — no dropdown UI on navigation
buttons, and users largely don't know it's there. Closed tabs are simply gone;
`TFileViewNotebook` (`src/ufileviewnotebook.pas`) frees the page.

**Proposed change:**

1. Put Back/Forward buttons with dropdown arrows at the left of each path bar (this pairs with
   the breadcrumb work in item 2). The dropdown lists that tab's history entries from
   `TFileViewHistory`, current position marked; selecting one calls the existing
   `GoToHistoryIndex`-style navigation.
2. On tab close, serialize the page state (path, file source chain, history, lock state — the
   notebook already knows how to save tabs for session restore) into a bounded "recently closed"
   ring (say, 20 entries) held by the notebook pair.
3. `cm_ReopenLastClosedTab` (suggest `Ctrl+Shift+T`) restores the newest entry into the side it
   was closed on; the tab context menu gets a "Recently closed ▸" submenu listing the ring.

**Implementation sketch:** Tab serialization for session save/restore already exists (tabs
survive restarts), so reopen-closed-tab is mostly *retargeting existing persistence at an
in-memory ring*. The history dropdown is pure UI over `ufileviewhistory.pas`.

---

## 10. File labels: user-assigned colors and tags that stick to files

**What DOpus does:** You can assign a **label** (a color, bold/italic style, and/or a small
status icon) to any file or folder — from the context menu — and it shows everywhere that item
appears: any folder view, search results, flat view. Labels can be stored per-path or in NTFS
ADS. Typical use: mark folders "in progress" green, "archived" gray, flag files to review.
This is different from extension-based coloring: it's *per-item, user-assigned state*.

**What DC does today:** File coloring exists only as rule-based colors by mask/attributes in the
options (configured once, applies by pattern). There is no way to say "this specific folder is
green now." Selecting/marking is transient and lost on reload.

**Proposed change:**

1. A small set of default labels (e.g. Red/Orange/Green/Blue/Gray + "custom…") on the context
   menu under **Label ▸**, assignable to any selection; assigning writes to a label store and
   repaints.
2. Storage: a per-config-dir SQLite or XML map of absolute path → label (portable, works on all
   file systems), with paths updated on rename/move performed inside DC. (ADS/xattr storage can
   be a later backend; path-keyed storage is simple and covers the main use.)
3. Rendering: labels resolve in the same place rule-based file colors are applied when a
   `TDisplayFile` is prepared for drawing — label color wins over extension color. A 8×8 colored
   dot before the name (in addition to text color) keeps labels visible for color-blind users
   and in selected rows.
4. Labels appear in *every* view of the item — columns, brief, thumbnails, flat view, search
   results — because resolution happens at display-file preparation, not per-view.

**Implementation sketch:** New small unit `ufilelabels.pas` (store + lookup with a path-prefix
cache); hook points in the display-file property loading in `ufileviewworker.pas` and the color
resolution used by `ucolumnsfileview.pas` drawing; context-menu additions in the file-panel
popup construction in `fmain.pas`/`umaincommands.pas`.

---

## Suggested implementation order

Ranked by (impact on daily feel) ÷ (effort), highest first:

1. **#1 FAYT multi-mode bar** — mostly one frame; transforms keyboard use.
2. **#9 History dropdowns + reopen tab** — thin UI over existing state.
3. **#3 Automatic folder sizes** — orchestration of existing operations.
4. **#7 Jobs bar** — highest "feel" payoff; medium UI effort, backend exists.
5. **#2 Breadcrumb bar** — contained in one control + `fmain.pas` wiring.
6. **#5 Inline rename upgrades** — localized to one unit.
7. **#4 Flat view promotion** — small changes, big discoverability win.
8. **#6 Navigation lock** — small coordinator, careful re-entrancy.
9. **#8 Viewer pane layout** — layout surgery in `fmain.pas`, async viewer work.
10. **#10 File labels** — new subsystem, but small and self-contained.

A follow-up batch can cover: Everything/locate-style indexed search integration, details+thumbnails
combined display mode, tab groups, status-bar disk gauges, "copy queue on collision" prompts with
per-queue answers, folder thumbnails, and toolbar three-button/menu buttons.
