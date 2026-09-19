# doublecmd progressive listing — HANDOFF

Updated: 2026-09-20

## Goal

Make huge directories (80K–millions of files, often on slow SMB shares)
usable while they are still being listed: first files on screen within
~100 ms, list grows, GUI never stalls. Small dirs (< 1000 files) load as before.

## Stage

Implemented, clean release build, verified on a synthetic 300k-file local dir
with window captures + a GUI-latency probe (WM_NULL every 100 ms):

| metric (300k local files)      | before        | now      |
|--------------------------------|---------------|----------|
| first files visible            | ~9 s          | ~0.1 s   |
| full list + icons              | ~9 s          | 2.2 s    |
| worst GUI stall during load    | ~7 s (hash)   | 58 ms    |

NOT yet tested on the real target `\\beyondinsane\B\Aardvark\books5`
(1.7M files, 8 min raw enumeration). Committed as 778dc7763, pushed to banana/master.

## How it works

- `TFileSourceListOperation.CheckProgress` ([src/filesources/ufilesourcelistoperation.pas](src/filesources/ufilesourcelistoperation.pas))
  fires `OnProgress` on the op's thread every 100 ms; filesystem list op calls
  it after each `FFiles.Add`.
- `TFileListBuilder.ListOperationProgress` ([src/fileviews/ufileviewworker.pas](src/fileviews/ufileviewworker.pas)):
  publishes a *prefix* of the files listed so far, size 1000 → doubling, but
  only when `elapsed since last publish >= 3 × (size × measured per-file
  build cost)`. Bounds overhead to ~1/3 of wall time on any source speed.
  Otherwise sends a count-only progress tick.
- Hash tables (`FHashedFiles`, `FHashedNames`) are built on the worker
  (`BuildFileHashes`) and swapped in; the view hands its old lists back via
  the `var` params so the worker frees them (`TakeFileLists` in
  [src/fileviews/ufileview.pas](src/fileviews/ufileview.pas)). Thumbnail
  bitmaps are released on the GUI thread first.
- `IsLoadingFileList` is False while a partial list is shown → all
  keyboard/mouse gates open. Final `SetFileList` carries selection over by name.
- Info panel: "Loading file list... N files" before the first partial list,
  then normal stats + "(still loading...)".

## Changed

- `src/upointerset.pas` — NEW: O(1) pointer hash set. Replaces `TBucketList(bl256)`,
  which was O(n) per op → 7 s for 300k files (pre-existing bottleneck).
- `components/doublecmd/dcstringhashlistutf8.pas` — `BeginBulk/EndBulk` (append
  then one sort; was O(n²) sorted-insert), capacity doubling in `Insert`.
- `src/filesources/ufilesourcelistoperation.pas` — `OnProgress`, `CheckProgress`.
- `src/filesources/filesystem/ufilesystemlistoperation.pas` — `CheckProgress` calls.
- `src/fileviews/ufileviewworker.pas` — publish logic, `BuildFileHashes`,
  `FileHashKey`, `AddUpDirIfNeeded`/`RetrieveSortingProperties` factored out;
  `TSetFileListMethod` now also carries the two hash tables.
- `src/fileviews/ufileview.pas` — `SetPartialFileList`, `TakeFileLists`,
  `CarrySelectionOver`, `SetLoadingFileListProgress`, `IsLoadingFileList`,
  `HashFileList` → `BuildFileHashes`, `ReDisplayFileList` allowed on partial.
- `src/fileviews/ufileviewwithpanels.pas` — info panel texts.
- `src/uglobs.pas` — `gProgressiveListing` (True), `gProgressiveListingMinFiles`
  (1000); doublecmd.xml keys `ProgressiveListing`, `ProgressiveListingMinFiles`.
  No options-page UI.
- `src/ulng.pas` — `rsMsgLoadingFileListCount`, `rsMsgStillLoadingFileList`.

## Decisions

- No "count first": Win32 cannot count a dir cheaply. Threshold applied to the
  running count; the 100 ms tick means fast local dirs never partial-publish.
- Cost-paced prefix publishing instead of "N at a time" or time-only ticks:
  a time-only tick on a fast local disk produced a 261k-file "partial" that
  cost seconds and delayed everything (measured).
- Progressive only for fresh loads in threaded mode; reload of the same path
  keeps the old list until complete (preserves selection/cursor).
- Only the filesystem list op reports progress; archives/WFX unchanged.

## Open / Next

1. Test on the SMB share `\beyondinsaneBAardvarkbooks5`.
2. Sort-order change during a long load is not applied to the final list
   (pre-existing, now more visible). Fix: re-sort in `SetFileList` if
   `SortingForSorter` differs from the worker's captured sortings.
3. Partial rows show generic icons until the final list (property retriever
   worker is queued behind the create worker). Cosmetic.
4. Memory: ~1.5 KB per file → ~2.6 GB for 1.7M files, transiently ×2 at the
   final swap. Pre-existing per-file footprint.

## Gotchas

- Build: `C:\lazarus\lazbuild.exe src\doublecmd.lpi --bm=release`; rename a
  running `doublecmd.exe` to `.old` first. Any edit of `ufileview.pas` trips the
  stale-PPU flake (`EListError` in unetworkthread/upixmapmanager) → `clean.bat`,
  `build.bat components` (PATH incl. `C:\lazarus`), rebuild. ~35 s.
- Test instance without touching the user's config:
  `doublecmd.exe --no-splash --debug-log=<f> --config-dir=<tmp> -L <dir>`;
  `{$DEFINE timeFileView}` in ufileview/ufileviewworker prints phase timings.
  Capture only the DC window with `PrintWindow(hwnd, hdc, 2)` — never the
  desktop. Close with `CloseMainWindow()` so the log flushes.
- FPC: fields cannot follow methods in a visibility section; a plain function
  declared inside a `type` block needs a new `type` keyword after it.
- `DoSetFileList` calls `DoneWorking`; the partial variant must not.
- `TStringHashListUtf8` Find/Remove must not be called between
  `BeginBulk`/`EndBulk` (list is unsorted then).
