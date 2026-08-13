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
