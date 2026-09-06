# Swag Scope Image Viewer Backlog

The current viewer already navigates sibling images, pans, zooms, fits, shows actual pixels,
rotates in either direction, mirrors either axis, resets its temporary transform, and presents
GIF, APNG, and WebP animations on a timeline. The same selector browses TIFF pages, ICO variants,
PSD layers, texture subresources, and OpenEXR parts. This backlog owns professional inspection around the codecs;
missing codec and pixel-format work remains in [std.pixel.image.md](std.pixel.image.md), while
render primitives remain in [std.pixel.md](std.pixel.md).

## Inspection and presentation

### app.scope.image.001 — The image has no pixel probe or measurement tools

- Evidence: zoom and pan never expose image coordinates, RGBA/channel values, premultiplied versus
  straight color, palette index, physical resolution, or distance/angle between points.
- Next: add a pointer/caret pixel inspector over decoded image coordinates, followed by a
  non-destructive line/rectangle measurement overlay.
- Complete when: coordinates and exact stored/converted channel values are copyable, alpha and
  out-of-bounds states are explicit, keyboard movement reaches individual pixels at high zoom, and
  distance/size can be reported in pixels and physical units when resolution metadata exists.

### app.scope.image.002 — Image analysis has no histogram, channel, clipping, or transparency views

- Evidence: the viewer renders the composite only. It cannot isolate R/G/B/A or luminance, show
  per-channel histograms, mark clipped shadows/highlights, visualize alpha, or inspect indexed
  palettes.
- Next: compute cancellable bounded histograms and add temporary channel/transparency overlays.
- Complete when: histogram scope states whole image or selection, high-bit-depth data is binned
  without forced 8-bit loss, channels and alpha can be inspected independently, clipping thresholds
  are configurable, and palette entries link to image pixels.

### app.scope.image.003 — Color management and HDR state are invisible to the reader

- Evidence: std.pixel.001/std.pixel.image.019 record that the pixel stack has no colour/ICC handling. The image
  panel reports pixel format and total bit depth, but not interpreted profile, transfer function, primaries,
  conversion, monitor target, or out-of-gamut/clipping status.
- Next: define the viewer information and soft-proof controls now, then connect them to the pixel
  color pipeline as it lands.
- Complete when: source and display color spaces are named, embedded profiles can be inspected,
  untagged assumptions are explicit, color conversion can be toggled for diagnosis, HDR content
  has a declared tone-map/output path, and screenshots never silently redefine source values.
- Related: std.pixel.001, std.pixel.image.019, std.pixel.002, std.pixel.003

### app.scope.image.004 — Source orientation is not distinguished from the temporary view transform

- Evidence: the viewer has a complete non-destructive dihedral view transform and its information
  panel reports EXIF orientation, but there is no normalized orientation value. Coordinate consumers have no
  shared source-to-display coordinate contract.
- Next: expose normalized source orientation through app.scope.image.011, then define one coordinate mapping for
  image dimensions, pan, selection, probes, animation frames, and the products in app.scope.image.009.
- Complete when: source orientation and temporary orientation are stated separately; every image
  coordinate consumer agrees with the displayed transform; raw export keeps source bytes; and
  rendered export declares the applied orientation.
- Related: app.scope.image.011

### app.scope.image.005 — Zoom lacks navigator, numeric entry, interpolation choice, and comparison scale

- Evidence: the information band now exposes a clickable percentage with common presets, actual
  size, and fit. There is no arbitrary numeric entry, fit-width/height, overview navigator,
  pixel-grid threshold, nearest-versus-smooth sampling control, or lockable scale across sibling
  images.
- Next: add arbitrary numeric entry, a small optional navigator, and sampling mode to the existing
  zoom control.
- Complete when: numeric zoom, Fit All/Width/Height, pixel grid, and sampling policy are explicit;
  the navigator shows and moves the viewport; and next/previous can preserve zoom and image-center
  coordinates when requested.

### app.scope.image.006 — Images cannot be compared side by side, overlaid, or by difference

- Evidence: sibling navigation replaces the current image. There is no synchronized pair, flicker,
  opacity wipe, difference/heat map, alignment, or per-pixel delta readout.
- Next: build a two-image comparison surface on app.scope.001 with synchronized transform and an explicit
  alignment anchor.
- Complete when: side-by-side, overlay, flicker, absolute difference, and heat-map modes work;
  pan/zoom can synchronize; size/color-space mismatches are stated; and the pixel probe reports
  both values plus delta.
- Related: app.scope.001

### app.scope.image.007 — Animated images have no frame-step, speed, loop, or disposal inspection

- Evidence: GIF, APNG, and WebP playback share play/pause, a frame slider, and frame count. There are no previous/
  next-frame commands, exact frame delay, playback speed, loop override, disposal/blend metadata,
  composited-versus-raw frame view, or dropped-frame indicator.
- Next: expose animation frame metadata and complete the transport around the existing cached movie.
- Complete when: frame stepping is exact, delay and timestamp are visible, 0.25x–4x and loop policy
  are selectable, raw and composited frames can be compared, and invalid timing/disposal warns.

### app.scope.image.008 — The image-set selector has no item descriptions or thumbnails

- Evidence: `ImageViewer` now browses every indexed format through `Movie` and a shared slider;
  `viewer.imageset.test.swg` covers all nine multi-image codec paths, including unequal dimensions.
  The slider and counter do not show the selected item's kind, name, dimensions, mip/layer/face
  coordinates, or thumbnail, although `ImageFrameInfo` already supplies the indexed properties.
- Next: present those properties and lazy thumbnails in a collection selector over the existing
  reader, keeping animation playback distinct from independent-image selection.
- Complete when: item identity survives view changes and the selector shows each item's description,
  dimensions, thumbnail, and format-specific relationships without decoding the whole collection.

### app.scope.image.009 — The displayed image cannot be copied or exported with an explicit transformation policy

- Evidence: there is no Copy Image, Copy Pixel Value, Copy View, Save Decoded As, or Save Frame
  command. A reader cannot tell whether orientation, color conversion, alpha, animation compositing,
  or zoom would affect output.
- Next: define raw, decoded-source, and rendered-view interchange products and expose only the forms
  the codec/pixel stack can produce faithfully.
- Complete when: clipboard and export name dimensions, pixel format, orientation, color space,
  alpha, and frame/page; raw extraction never transcodes; rendered output declares conversions;
  and large exports are cancellable.

### app.scope.image.010 — Huge and damaged images cannot degrade progressively

- Evidence: `Movie.maxCacheBytes` now bounds cached frames to 64 MiB by default and `DecodeOptions`
  bounds input, frame count, and per-image storage. The background loader still publishes its first
  image only after a complete decode and cache preparation; no partial image or region reaches the
  viewer while slow storage or decoding is in progress.
- Next: connect progressive or region decoding to background publication, beginning with one large
  raster format and retaining the existing cache ceilings.
- Complete when: metadata and a bounded preview appear before full decode where possible, visible
  tiles have priority, animation cache has an explicit budget, cancellation is prompt, and partial
  damage is marked without discarding valid regions.
- Related: app.scope.viewers.004, std.pixel.image.038, std.pixel.image.039

This backlog covers image-viewer behavior owned by Swag Scope. Decoder, SVG, and pixel-format work
remains in [std.pixel.image.md](std.pixel.image.md), while the general color contract remains in
[std.pixel.md](std.pixel.md); this file owns the metadata and format composition presented by the
application.

## Metadata and camera files

### app.scope.image.011 — Orientation, ICC identity, and XMP remain incomplete

- Evidence: the information panel shows preserved PNG text and interpreted JPEG EXIF fields.
  Encoded orientation is reported but not applied; ICC records have only a byte count and XMP
  properties are not interpreted.
- Next: apply encoded orientation exactly once and expose ICC identity and readable XMP fields.
- Complete when: EXIF orientation is applied on load and the panel identifies embedded profiles
  and presents supported XMP properties.
- Related: std.pixel.001, std.pixel.image.019

### app.scope.image.012 — Camera RAW files show nothing

- Intent: extract an embedded JPEG preview when a supported camera RAW container carries one.
  Full RAW development is out of scope; a missing or unsupported preview must be stated explicitly.
- Complete when: the embedded preview of the common TIFF-based RAW containers is extracted and
  displayed, with the metadata panel from app.scope.image.011 beside it.
- Related: app.scope.image.011
