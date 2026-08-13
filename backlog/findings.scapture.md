# Findings — sCapture

Evidence about the sCapture application itself: what will be fixed under
`bin/apps/modules/sCapture`. Intent for the same unit is [todo.scapture.md](todo.scapture.md).

A lead that sCapture exposed but that will be fixed in `std/gui` belongs in
[findings.gui.md](findings.gui.md) instead — the file follows the fix, not the discovery.

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

## Window automation and lifecycle

### F-040 — sCapture dies when its window is moved and resized in one call

- Area: apps/sCapture, std/gui
- Found while: driving the shipped window from a script to photograph its pages. The window opens
  maximized across a two-monitor desktop, so a capture has to bring it back onto one screen first.
- Observation: `SetWindowPos(hwnd, HWND_TOPMOST, 40, 40, 2400, 1500, 0)` — one call that moves,
  resizes and raises — kills the process three times out of four. The same call with `SWP_NOSIZE`
  (move only) has never killed it. Dragging the window by hand does not either, which is why the
  application looks healthy in normal use.
- Evidence: reproduced from a plain PowerShell driver against the packaged build, four attempts,
  three deaths, no window left behind. `GetWindowRect` on the survivor returns the requested
  rectangle, so the call itself succeeds before the process goes.
- Did NOT reproduce on 2026-08-06: four fresh runs of the identical call, four survivals, the
  window landing exactly on the requested 40,40 2400x1500 each time. The window opened at
  268,73 2821x1563 — on one monitor and not maximized — so the DPI boundary this entry suspects
  was never crossed. That is a negative result about the driver, not about the defect: the
  reproduction has to start from the maximized two-monitor state the original run had, or the
  call never does the thing that kills it.
- Suspicion, not conclusion: the two monitors of this desktop are at different scales, so that one
  call crosses a DPI boundary *and* changes the client size in the same message. The surface
  rebuilds its render target on a size change and re-reads its scale on a DPI change; doing both
  from one message is the path a hand-drag never takes.
- Next step: reproduce with a minimal `gui2`-sized example under the same two-monitor arrangement,
  then bisect: move-only across the boundary, resize-only on one screen, then both. If it is the
  DPI crossing, `Surface` is where the ordering of the two rebuilds is decided. Move this entry to
  [findings.gui.md](findings.gui.md) once that bisection puts the defect in `Surface`.

## Library scale

### F-112 — A capture stores its images uncompressed, and the library reads all of them whole

- Area: apps/sCapture, std/core (serialization), std/pixel
- Found while: measuring why the library grid crawls on a real library. The grid work itself was a
  separate defect and is fixed; this is what remained underneath.
- Observation: capture previews cannot be read without transferring the full, uncompressed image
  payloads from disk.
- Evidence: the author's library holds 742 captures for 11.7 GB — 15.8 MB per capture on
  average, up to 95.9 MB for one. A capture at 1920x1080 in BGRA8 is 8.3 MB of pixels, and a
  capture stores two of them (`backImg` and `backImgOriginal`), which is the average almost
  exactly. `Image.pixels` carries no `Serialization.Compress`, so those pixels travel raw. The
  sizes are not new: the 2024 files already average 11 MB.
- Second half of the cost: `Capture.load` reads the file with `File.readAllBytes` before it
  decodes anything, so the preview load the library performs — which asks TagBin to ignore
  `backImg` and `backImgOriginal` — still reads every one of those bytes off the disk. Showing a
  256-pixel thumbnail for the whole library moves 11.7 GB.
- Measured: 250 real captures, warm cache, `Capture.load(preview: true)` costs 9.7 ms each,
  2.4 s for the 250; the raw `File.readAllBytes` pass over the same 250 moves 3.9 GB. A synthetic
  probe over a TagBin stream carrying a 200 KB compressed payload decodes in 459 us against 79 us
  when the payload is ignored, so the decode is not what dominates — the bytes are.
- Next step: two independent moves, either of which stands alone.
  1. Compress the pixel payload. `#[Serialization.Compress]` on `Image.pixels` costs a deflate
     pass per save and shrinks a screen capture by a large factor; check what it does to save
     latency before adopting it, since a capture is saved interactively.
  2. Stop reading the whole file to answer a preview. The container header is already versioned
     (`CaptureFileMagic`), so a preview offset (or a sidecar) would let the library read a few
     kilobytes per capture instead of megabytes. This is the move that makes the library scale
     regardless of what the pixels cost.

## Editor interactivity

### F-126 — The one-second auto-save freezes the interface for the duration of a full deflate

- Area: apps/sCapture
- Found while: making a form drag fluid. The per-move repaint and the mid-gesture save are fixed
  (the save timer now waits for the gesture to end); this is the cost that remains.
- Observation: one second after an edit burst, `RecentWnd.onTimerEvent` rebuilds the preview
  (GPU render + read-back + PNG encode) and runs `Capture.save`, all on the interface thread.
  The save TagBin-encodes and deflates `backImg` *and* `backImgOriginal` on every save, although
  the original never changes after the capture is taken. On a large capture (a 4K grab is ~33 MB
  of BGRA per image) the whole thing is a visible freeze, felt right after every adjustment.
- Evidence: `Capture.save` in [capture.swg](../bin/apps/modules/sCapture/src/capture.swg)
  re-encodes both image chunks unconditionally (`encodeValue(&.backImg)`,
  `encodeValue(&.backImgOriginal)`, both under `codecDeflate`); the timer path is
  `RecentWnd.onTimerEvent` in [recentwnd.swg](../bin/apps/modules/sCapture/src/recentwnd.swg).
- Next step: cache the encoded+deflated `backImgOriginal` chunk on the `Capture` (invalidated the
  rare times the original changes, e.g. RestoreOrg/Flatten) and hand the pre-compressed bytes to
  `Scc.Writer`, which halves the save; then measure whether the remaining `backImg` deflate is
  small enough, or whether the save must move off the interface thread (which needs a snapshot of
  the form list to stay race-free).
- Related: F-112 (storage compression and preview reads for the same files).
