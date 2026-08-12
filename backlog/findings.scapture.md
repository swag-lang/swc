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

## Paint cost

### F-120 — A form's shadow blurs a layer 200 px larger than the form on every side

- Area: apps/sCapture, std/pixel (`RenderCpu`, `Layer.buildShadow`)
- Found while: asking why `swc tools/apps.swgs test sCapture` took minutes. Starting the shared
  worker pool in `Gui.Testing.HeadlessHost`, which a host had never done because it bypasses
  `Application.createSurface`, took the suite from 1 min 43 s to 25 s. That is the same work
  spread over 22 cores; everything below is still being computed.
- Observation: `Capture.paintForm` inflates a form's bound rectangle by `FormPaintOverdraw` (200)
  on every side before allocating the layer it paints into, so a 30x25 shape is drawn through a
  420x420 layer. `LayerDrawInfo.shadow` is then enabled for it, and `Layer.buildShadow` blurs that
  whole layer twice. On the GPU backend those passes are a fragment shader nobody notices; on
  `RenderCpu`, which is the backend every headless test runs on, each blurred pixel walks 17 taps
  of `sampleBlur`, and each tap is a bilinear fetch plus a `Math.exp` call.
- Evidence: measured 2026-08-12 in `fast-debug`, serial, with a temporary probe in the module and
  a per-test timer in `bin/runtime/tests.swg`:
  - `Capture.toImage` on an empty 400x300 capture: 47 ms. With one rectangle whose shadow is on:
    1606 ms. Same shape with `paintShadow = false`: 117 ms. Adding one text form: 1901 ms with
    its shadow, 394 ms without. So one shadow costs ~1.5 s.
  - The instrumented `buildShadow` reports `layer 420x420 dev 436x436` for that 30x25 shape, and a
    counter in the blur path reports 380_192 blurred pixels for the one shadow — 4.7 us each.
  - It is the whole shape of the suite: the six slowest tests held 81 s of the 97 s of test time,
    and every one of them paints forms. The fixture itself is free — `HeadlessFixture.setup` plus
    `shutdown` measures 1 ms, and the theme atlases are rasterized once per process.
- Next step: three independent moves, in decreasing value.
  1. Size the layer to what the form actually needs. 200 px on every side is 200x the area of a
     small form; the overdraw a form really needs is its stroke, its caps, and its shadow radius
     plus offset. `FormPaintOverdraw` is one constant in `tweak.swg` used by both the painter and
     the cull test, so the two have to move together.
  2. Bound the blur to the content. `buildShadow` blurs `shadowWidth x shadowHeight` whatever the
     content covers, so the padding an oversized layer carries is blurred as well as the form.
  3. Make a CPU blur tap cheaper: the Gaussian weights depend only on the radius, so the kernel
     can be built once per pass instead of calling `Math.exp` per tap per pixel.