# Swag Capture Backlog

This file records the product outcomes and investigations for Swag Capture, including its
use of shared `bin/std` facilities.

Evidence, investigations, and intended outcomes owned by the application stay together here.
Operating-system work belongs in [platform.portability.md](platform.portability.md); compiler and language work
belongs in [compiler.core.md](compiler.core.md) and [language.design.md](language.design.md).
[README.md](README.md) has the whole layout.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

## Where Swag Capture already stands

The annotation model has nine form types over one shared style base, nested groups, z-order,
alignment, snapping, per-capture undo, quick styles, and a reflective property panel with undo.
Area capture detects the window under the cursor, and the in-place editing overlay annotates the
frozen desktop before the result is copied or opened in the editor.

The gaps are elsewhere: capture modes beyond a still rectangle, text recognition, the layer of
effects that makes a capture look produced, and output.

---

## Tier A — Output and text extraction


### app.capture.001 — Print the current capture

Add actual-size, fit-to-page, and centered printing with a clear clipping warning. Consume the GUI
pagination/preview contract and Pixel vector output rather than creating an application-only print
path.

- Related: std.gui.030, std.pixel.005, std.gui.034


## Tier A — Capture effects

### app.capture.002 — No capture-level effect pipeline

- `Capture` has geometry, a background image, and forms, but nowhere to store and order effects.
  Add an effect list applied identically by preview, flatten, and export, with the property panel
  generated through the existing reflective editor system.
- Priority: shared capture effects would apply to preview, flatten, and export through one model.
- Related: app.capture.003, app.capture.005, app.capture.007, app.capture.008, std.pixel.012

### app.capture.003 — No capture border effect

Add border width, color, placement, and corner interaction as the first effect using app.capture.002.

- Related: app.capture.002, app.capture.004

### app.capture.004 — No capture drop-shadow effect

Add a drop shadow with offset, blur, spread, and color through Pixel's effect graph.

- Related: std.pixel.012, app.capture.002, app.capture.003

### app.capture.005 — No torn-edge capture effect

Add deterministic torn-edge mask generation with scale-independent parameters.

- Related: app.capture.002, app.capture.006

### app.capture.006 — No faded-edge capture effect

Add a faded-edge mask independently of torn-edge generation.

- Related: app.capture.002, app.capture.005

### app.capture.007 — No capture perspective effect

Add perspective transformation with explicit output bounds and resampling behavior.

- Related: app.capture.002

### app.capture.008 — No capture watermark effect

Add reusable image/text watermarks with placement, opacity, scale, and export persistence.

- Related: app.capture.002

## Tier A — Capture workflows

### app.capture.009 — Capture hotkeys are fixed

- `MainWnd.registerShortcuts` registers four fixed combinations. Persist user-rebindable hotkeys in the
  existing options and let the user resolve conflicts. Registration failures already produce an
  information bar naming the unavailable shortcut.
- A shortcut can already be owned by another application; rebinding provides a recovery path.
- Related: app.capture.010

### app.capture.010 — No named capture presets

Persist named combinations of capture mode, delay, cursor policy, and destination, then allow app.capture.009
to bind a hotkey to a preset rather than a raw command.

- Related: app.capture.009

---

## Tier C — Scrolling and recorded capture

Recording requires a timed acquisition and export subsystem. Keep these outcomes behind the
still-image editing and output work above.


### app.capture.011 — No video recording

- Add a timed frame-capture loop and hardware video encoder with bounded buffering and observable
  dropped-frame behavior.
- Recommendation: treat it as a deliberate decision rather than an assumed goal. A still-capture
  tool with an outstanding editor is a coherent product. A half-finished recorder is not.
- Related: app.capture.012, app.capture.013, app.capture.014

### app.capture.012 — No animated GIF recording

Record and export an animated GIF independently of the video codec pipeline, with a stated frame
rate, palette, dithering, and size contract.

- Related: app.capture.011

### app.capture.013 — Recordings cannot include audio

Capture microphone or loopback audio and mux it into video without making audio a prerequisite for
silent recording.

- Related: std.audio.011, std.audio.013, app.capture.011

### app.capture.014 — Recordings cannot be trimmed in the editor

Add non-destructive in/out trimming and export for captured recordings after the base recorder can
produce a playable artifact.

- Related: app.capture.011, app.capture.012

---

## Tier D — Canvas composition and reusable annotations

### app.capture.015 — Captures cannot be combined on one canvas

Compose several captures into one editable, laid-out image using the existing form model.

- Related: app.capture.016

### app.capture.016 — No reusable capture layout templates

Persist and apply named layout descriptions independently of combining captures manually.

- Related: app.capture.015

### app.capture.017 — Stamp library

A reusable graphics set placed as `FormImage` instances. Small, and it fits the existing model
exactly. Must follow the identity rules in `design-swag-identity` rather than shipping generic
clip art.

## Out of scope

**Hosted share destinations.** Service integrations add authentication, credential storage, and
API maintenance outside this application's current scope. Local outputs — clipboard, file,
drag-out, print, and `mailto` — are the intended integration boundary; platform.portability.068
owns the operating-system work.

**Machine-learning editing features.** Snagit's object detection and text replacement are model
work. They belong to a company shipping a capture product, not to an application demonstrating a
language.

**Mobile and webcam capture.** Neither fits what this application is for.

---

The entries below were open investigations when the unified backlog was introduced. Update their
next action in place as the evidence matures. They retain their former order until re-triaged, so
position in this imported block carries no priority claim.

These application-specific leads will be fixed under `bin/apps/modules/swagcapture`.

A lead that Swag Capture exposed but that will be fixed in `std/gui` belongs in
[std.gui.md](std.gui.md) instead — the file follows the fix, not the discovery.

## Window automation and lifecycle

### app.capture.019 — Swag Capture dies when its window is moved and resized in one call

- Area: apps/swagcapture, std/gui
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
  [std.gui.md](std.gui.md) once that bisection puts the defect in `Surface`.

## Editor interactivity

### app.capture.021 — Loading a capture blocks the interface during decode

- Evidence: `RecentView.select` in `src/recentwnd.swg` flushes a pending save of the selected
  file, then calls `Capture.load` synchronously. The recent strip already has its preview.
  On the photographed 2341x1903 BGRA8 capture measured on 2026-08-15, the original load cost
  431 ms; the subsequent inflate rewrite reduced it to about 210 ms. Both are historical
  measurements of the same synchronous path, not current timing guarantees.
- Next: make selection an owned asynchronous load that leaves the preview visible, respects
  outstanding saves, and publishes only the result of the latest selection. Define cancellation,
  failure presentation and window-close cleanup before moving the decode off the interface thread.
- Complete when: delayed loads cannot freeze input or replace a newer selection, failed loads
  leave a useful preview and diagnostic, and shutdown joins outstanding work.
- Related: app.capture.024, app.capture.025, language.parallelism.001

### app.capture.024 — Revisiting a recent capture decodes its full image again

- Evidence: `RecentView` retains previews and zoom state in `src/recentwnd.swg`; selecting an
  inactive item calls `Capture.load` again. The historical library sample averaged 7 MB of decoded
  pixels per capture and reached 47 MB, so retaining every decoded capture is not a bounded policy.
- Next: define a decoded-capture cache bounded by bytes, with ownership of the active editable
  capture, save completion and on-disk replacement included in its invalidation contract.
- Complete when: revisiting an unchanged cached capture avoids decode, a modified/replaced file
  cannot reuse stale content, and the cache obeys its byte bound after selection and eviction.
- Related: app.capture.021

### app.capture.025 — Capture image chunks have no measured alternative to deflate

- Evidence: capture persistence uses `Core.Scc` chunk codecs. The photographed payload measured
  on 2026-08-15 compressed from 17.0 to 12.8 MB at BestSpeed and to 12.5 MB at the slower settings;
  PNG decoded in 377–409 ms. Those measurements motivate a codec decision, not a format migration
  without a representative corpus.
- Next: compare stored and faster lossless chunk encodings on the same capture corpus, recording
  decode CPU, peak memory and file size. Keep existing files readable through their codec id.
- Complete when: a documented selection rule has measured benefits on representative captures,
  and any new encoding round-trips with compatibility tests for existing deflate files.
- Related: app.capture.021, compiler.optimization.006

### app.capture.023 — A property painter reading a stale selection is only caught in devmode

- The bug is fixed; what remains is that the headless panel does not reproduce it, so nothing
  guards the painters themselves.
- What happened: `PropWnd.propShape` checks the selected kind when it creates its button, but the
  `iconPainter` it installs runs on every frame and cast whatever was selected *then* to
  `*FormShape`. Selecting a text form put a `String`'s first bytes where `kind` lives, and
  `drawShapeGlyph` switches over a three-value enum with `#complete`. Release has the guard off and
  drew a wrong glyph; devmode panicked. Six other painters and popup handlers had the same shape.
  All of them now ask `getSelectedForm'T()`, which answers null when the selection is not a `T`.
- Why there is no test for the painter: a headless fixture that builds the panel, moves the
  selection to a text form and renders each style button does not fault, with or without the fix —
  the buttons are laid out and painted and the value read still comes back inside the enum. The
  running application faults reliably. `propwnd.test.swg` therefore pins the accessor's contract,
  which is the mechanism, and not the painters that depend on it.
- Next: find what the headless render does differently — most likely which paint context the icon
  slot gets — and pin one painter against a deliberately mismatched selection.
- Complete when: reverting the guard in `propShape` makes a test fail.
