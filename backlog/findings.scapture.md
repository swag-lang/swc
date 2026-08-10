# Findings — sCapture

Evidence about the sCapture application itself: what will be fixed under
`bin/apps/modules/sCapture`. Intent for the same unit is [todo.scapture.md](todo.scapture.md).

A lead that sCapture exposed but that will be fixed in `std/gui` belongs in
[findings.gui.md](findings.gui.md) instead — the file follows the fix, not the discovery.

Conventions, the identifier counter, and the rest of the backlog are in [README.md](README.md).
Entries are sorted by identifier, ascending; position carries no priority.

## Window automation and lifecycle

### F-039 — The sCapture main window cannot be painted headlessly

- Area: apps/sCapture
- Found while: photographing both shipped surfaces in every palette, to review them without a
  desktop. sCrypt renders; sCapture faults.
- Observation: a headless host that builds the real window with `MainWnd.create(&gui.root)` — the
  same call `dialogs.test.swg` already makes and which succeeds — dies with an access violation
  (0xC0000005) as soon as that window is laid out and painted. Creating it and never painting it is
  fine, which is what every existing test does.
- Evidence: reproduced four times, in release, with and without a `Capture` set on the edit view,
  with and without `Library.init` through `testUseScratchLibrary`, and with and without a theme
  broadcast — the fault survives all six combinations, so it is neither the capture, nor the
  library, nor the harness change made in the same task. The 127 other tests of the module pass in
  the same binary.
- Narrowed (2026-08-06), and the bisection this entry used to propose is now ruled out:
  - creation and `applyLayout()` both complete; two `HeadlessHost.pump()` calls complete. The
    fault is on the FIRST PAINT — which is what `settleAnimations` and `render` do and what
    `pump` does not, since `pump` only drains the posted, destroy and delete queues.
  - hiding every direct child of the window before painting (`topBar`, `toolRail`, `recentBar`,
    `rightBar`, `editWnd`) does NOT avoid it. So it is not one subtree: it is the window's own
    paint, or the surface chrome painted around it.
- Next step: instrument the paint rather than the tree. `Surface.paintWnd` is the entry; find
  whether the fault is inside it or in the `readRenderTarget` that follows, then compare against
  `sCrypt`, whose main window paints through the same call — the difference is that sCrypt's
  window installs itself as the view of its surface (`MainWindow.create(&host.surfaceWnd)`) while
  sCapture's is built as a child of the host root (`MainWnd.create(&gui.root)`), so the two paint
  through different parents. Build the probe in `-bc debug`: a use-after-free reads clean in
  fast-debug and release.
- Why it matters beyond the crash: sCapture has 133 tests and none of them can see the window, so
  no appearance regression in the one application that *is* a visual tool can ever fail a test.
  The same photograph is one test away for sCrypt and impossible here.

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
