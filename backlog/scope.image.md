# Swag Scope Image Viewer Backlog

The current viewer already navigates sibling images, pans, zooms, fits, shows actual pixels,
rotates in either direction, mirrors either axis, resets its temporary transform, and presents
animated GIF frames on a timeline. This backlog owns professional inspection around the codecs;
missing pixel formats and render primitives remain in [pixel.md](pixel.md).

## Inspection and presentation

### B-096 — The image has no pixel probe or measurement tools

- Evidence: zoom and pan never expose image coordinates, RGBA/channel values, premultiplied versus
  straight color, palette index, physical resolution, or distance/angle between points.
- Next: add a pointer/caret pixel inspector over decoded image coordinates, followed by a
  non-destructive line/rectangle measurement overlay.
- Complete when: coordinates and exact stored/converted channel values are copyable, alpha and
  out-of-bounds states are explicit, keyboard movement reaches individual pixels at high zoom, and
  distance/size can be reported in pixels and physical units when resolution metadata exists.

### B-097 — Image analysis has no histogram, channel, clipping, or transparency views

- Evidence: the viewer renders the composite only. It cannot isolate R/G/B/A or luminance, show
  per-channel histograms, mark clipped shadows/highlights, visualize alpha, or inspect indexed
  palettes.
- Next: compute cancellable bounded histograms and add temporary channel/transparency overlays.
- Complete when: histogram scope states whole image or selection, high-bit-depth data is binned
  without forced 8-bit loss, channels and alpha can be inspected independently, clipping thresholds
  are configurable, and palette entries link to image pixels.

### B-098 — Color management and HDR state are invisible to the reader

- Evidence: B-207/B-314 record that the pixel stack has no colour/ICC handling, and the image
  viewer does not report embedded profile, transfer function, primaries, bit depth per channel,
  conversion, monitor target, or out-of-gamut/clipping status.
- Next: define the viewer information and soft-proof controls now, then connect them to the pixel
  color pipeline as it lands.
- Complete when: source and display color spaces are named, embedded profiles can be inspected,
  untagged assumptions are explicit, color conversion can be toggled for diagnosis, HDR content
  has a declared tone-map/output path, and screenshots never silently redefine source values.
- Related: B-207, B-314, B-315, B-316

### B-099 — Source orientation is not distinguished from the temporary view transform

- Evidence: the viewer has a complete non-destructive dihedral view transform, but decoded images
  do not expose EXIF orientation and future selection, pixel-probe, and export features have no
  shared source-to-display coordinate contract.
- Next: expose normalized source orientation through B-453, then define one coordinate mapping for
  image dimensions, pan, selection, probes, animation frames, and the products in B-104.
- Complete when: source orientation and temporary orientation are stated separately; every image
  coordinate consumer agrees with the displayed transform; raw export keeps source bytes; and
  rendered export declares the applied orientation.
- Related: B-453

### B-100 — Zoom lacks navigator, numeric entry, interpolation choice, and comparison scale

- Evidence: commands step zoom, fit, and actual size, with a percentage label. There is no direct
  percentage entry, fit-width/height, overview navigator, pixel-grid threshold, nearest-versus-
  smooth sampling control, or lockable scale across sibling images.
- Next: turn the zoom label into an addressable control and add a small optional navigator plus
  sampling mode.
- Complete when: numeric zoom, Fit All/Width/Height, pixel grid, and sampling policy are explicit;
  the navigator shows and moves the viewport; and next/previous can preserve zoom and image-center
  coordinates when requested.

### B-101 — Images cannot be compared side by side, overlaid, or by difference

- Evidence: sibling navigation replaces the current image. There is no synchronized pair, flicker,
  opacity wipe, difference/heat map, alignment, or per-pixel delta readout.
- Next: build a two-image comparison surface on B-448 with synchronized transform and an explicit
  alignment anchor.
- Complete when: side-by-side, overlay, flicker, absolute difference, and heat-map modes work;
  pan/zoom can synchronize; size/color-space mismatches are stated; and the pixel probe reports
  both values plus delta.
- Related: B-448

### B-102 — Animated images have no frame-step, speed, loop, or disposal inspection

- Evidence: GIF playback has play/pause, a frame slider, and frame count. There are no previous/
  next-frame commands, exact frame delay, playback speed, loop override, disposal/blend metadata,
  composited-versus-raw frame view, or dropped-frame indicator.
- Next: expose animation frame metadata and complete the transport around the existing cached movie.
- Complete when: frame stepping is exact, delay and timestamp are visible, 0.25x–4x and loop policy
  are selectable, raw and composited frames can be compared, and invalid timing/disposal warns.

### B-103 — Multi-image and multi-page formats have no collection model

- Evidence: animation frames are special-cased, while ICO alternatives appear in Binary and future
  TIFF/HEIF/PSD layers or pages have no common selector, labels, thumbnails, or hierarchy.
- Next: define an image-item collection that distinguishes animation frames, pages, resolutions,
  layers, mip levels, and embedded previews without pretending they share playback semantics.
- Complete when: every decoded item is enumerable and selectable, thumbnails load lazily, item
  identity survives view changes, and format-specific relationships and dimensions are visible.
- Related: B-321, B-322, B-324

### B-104 — The displayed image cannot be copied or exported with an explicit transformation policy

- Evidence: there is no Copy Image, Copy Pixel Value, Copy View, Save Decoded As, or Save Frame
  command. A reader cannot tell whether orientation, color conversion, alpha, animation compositing,
  or zoom would affect output.
- Next: define raw, decoded-source, and rendered-view interchange products and expose only the forms
  the codec/pixel stack can produce faithfully.
- Complete when: clipboard and export name dimensions, pixel format, orientation, color space,
  alpha, and frame/page; raw extraction never transcodes; rendered output declares conversions;
  and large exports are cancellable.

### B-105 — Huge and damaged images cannot degrade progressively

- Evidence: still images decode as one complete bitmap and animations cache all decoded frames.
  Extremely large dimensions, many frames, slow network storage, truncated scans, and crafted
  allocation claims can delay opening or exhaust memory before a useful partial view appears.
- Next: publish codec dimension/frame budgets and add tiled/progressive decode hooks beginning with
  one large raster format.
- Complete when: metadata and a bounded preview appear before full decode where possible, visible
  tiles have priority, animation cache has an explicit budget, cancellation is prompt, and partial
  damage is marked without discarding valid regions.
- Related: B-044

This backlog covers image-viewer behavior owned by Swag Scope. Decoder, color, SVG, and pixel-format
work remains in [pixel.md](pixel.md); this file owns the metadata and format composition presented
by the application.

## Metadata and camera files

### B-453 — An image's metadata is not shown

- Intent: no EXIF, no ICC, no XMP anywhere. Orientation is therefore ignored, so a phone photograph
  displays rotated, and camera, exposure and capture date are invisible.
- Complete when: a metadata panel shows the decoded tags, EXIF orientation is applied on load, and
  an embedded ICC profile is at least reported.
- Related: B-207, B-314

### B-461 — Camera RAW files show nothing

- Intent: full RAW development is out of scope, but every RAW file embeds a JPEG preview, and
  showing it is most of the value at a fraction of the cost.
- Complete when: the embedded preview of the common TIFF-based RAW containers is extracted and
  displayed, with the metadata panel from B-453 beside it.
- Related: B-453
