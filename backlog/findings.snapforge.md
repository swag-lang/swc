# Findings — sSnapForge

Evidence about the sSnapForge application itself: what will be fixed under
`bin/apps/modules/sSnapForge`. Intent for the same unit is [todo.snapforge.md](todo.snapforge.md).

A lead that sSnapForge exposed but that will be fixed in `std/gui` belongs in
[findings.gui.md](findings.gui.md) instead — the file follows the fix, not the discovery.

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

## Window automation and lifecycle

### F-040 — sSnapForge dies when its window is moved and resized in one call

- Area: apps/sSnapForge, std/gui
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

## Editor interactivity

### F-126 — The one-second auto-save freezes the interface for the duration of a full deflate

- Area: apps/sSnapForge
- Found while: making a form drag fluid. The per-move repaint and the mid-gesture save are fixed
  (the save timer now waits for the gesture to end); this is the cost that remains.
- Observation: one second after an edit burst, `RecentWnd.onTimerEvent` rebuilds the preview
  (GPU render + read-back + PNG encode) and runs `Capture.save`, all on the interface thread.
  The save TagBin-encodes and deflates `backImg` *and* `backImgOriginal` on every save, although
  the original never changes after the capture is taken. On a large capture (a 4K grab is ~33 MB
  of BGRA per image) the whole thing is a visible freeze, felt right after every adjustment.
- Evidence: `Capture.save` in [capture.swg](../bin/apps/modules/sSnapForge/src/capture.swg)
  re-encodes both image chunks unconditionally (`encodeValue(&.backImg)`,
  `encodeValue(&.backImgOriginal)`, both under `codecDeflate`); the timer path is
  `RecentWnd.onTimerEvent` in [recentwnd.swg](../bin/apps/modules/sSnapForge/src/recentwnd.swg).
- Next step: cache the encoded+deflated `backImgOriginal` chunk on the `Capture` (invalidated the
  rare times the original changes, e.g. RestoreOrg/Flatten) and hand the pre-compressed bytes to
  `Scc.Writer`, which halves the save; then measure whether the remaining `backImg` deflate is
  small enough, or whether the save must move off the interface thread (which needs a snapshot of
  the form list to stay race-free).

### F-137 — Loading a capture blocks the interface for the duration of one inflate

- Area: apps/sSnapForge, std/core (Compress)
- Found while: investigating the lag felt when clicking a capture in the recent strip. This is the
  load counterpart of [F-126](#f-126--the-one-second-auto-save-freezes-the-interface-for-the-duration-of-a-full-deflate);
  both come from the same decision to deflate raw pixels.
- Observation: `RecentView.select` calls `Capture.load` synchronously on the interface thread, and
  the whole cost of that load is inflating the background chunk. Nothing is shown in the meantime,
  although the capture's own preview is already decoded and on screen in the strip that was just
  clicked.
- Evidence: measured 2026-08-15, release config, on `8_9_2025_15_43_58.scapture` (13.5 MB on disk,
  a photograph, 2341x1903 BGRA8). Whole load 431 ms, of which the background chunk is 388 ms
  (12.8 MB read 12 ms, inflate ~350 ms, decoded CRC-32 ~25 ms); the TagBin decode of the image is
  9 ms, the model chunk 0.2 ms, the header 0.6 ms, the preview PNG 5 ms. The library holds 746
  captures, 4.01 GB on disk for 5.77 GB of decoded pixels, 7 MB of pixels per capture on average
  and 47 MB at worst — so the average click pays ~170 ms and the worst ~1.2 s.
- Since then (lever 4 below): the `Compress.Inflate` block loop was rewritten and the same load
  measures ~210 ms, the background chunk 200 ms. Halved, still blocking, still the whole load.
- Evidence that deflate is a bad trade on this content: a screen grab of a photograph does not
  compress. This payload goes 17.0 -> 12.8 MB (1.33x) at BestSpeed, and only 12.5 MB (1.36x) at
  Default or BestCompression; the whole library averages 1.44x. Re-encoding the same pixels as
  PNG gives 11.0 MB but decodes in 377-409 ms, because PNG is the same inflate plus unfiltering.
  So the current format spends ~350 ms of load to save ~30% of disk.
- Next step: three levers remain, in decreasing value and increasing cost.
  (1) Do not block the click: keep the preview on screen and swap in the full capture when the
  decode lands, which removes the *felt* lag whatever the codec does. (2) Keep the last few
  decoded captures alive in `RecentView`, since clicking back and forth through the history is
  exactly the gesture that reloads what was just discarded. (3) Make the chunk codec a decision
  instead of a constant: `Scc` already dispatches on a codec id, so a fast byte-oriented codec
  (LZ4-class, decoding at GB/s for a ratio near 1.2) or plain stored bytes for payloads that do
  not compress would cut the load to the read itself. Existing files keep loading through the
  deflate path, so this is additive.
  A fourth lever, making inflate itself fast, was taken and is where the halving above came from;
  what is left of it is a backend matter, in
  [F-136](findings.optimization.md#f-136--a-hot-loops-loop-carried-locals-all-live-in-stack-slots).
