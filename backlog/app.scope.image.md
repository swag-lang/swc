# Swag Scope Image Viewer Backlog

The current viewer already navigates sibling images, pans, zooms, fits, shows actual pixels,
rotates in either direction, mirrors either axis, resets its temporary transform, and presents
GIF, APNG, and WebP animations on a timeline. The same selector browses TIFF pages, ICO variants,
PSD layers, texture subresources, and OpenEXR parts. This backlog owns professional inspection around the codecs;
missing codec and pixel-format work remains in [std.pixel.image.md](std.pixel.image.md), while
render primitives remain in [std.pixel.md](std.pixel.md).

### app.scope.image.012 — Camera RAW files show nothing

- Recorded: 2026-08-17 11:01
- Updated: 2026-09-12 05:46 — Refer to the existing metadata panel after orientation work was split
- Intent: extract an embedded JPEG preview when a supported camera RAW container carries one.
  Full RAW development is out of scope; a missing or unsupported preview must be stated explicitly.
- Complete when: the embedded preview of the common TIFF-based RAW containers is extracted and
  displayed, with its source and preview metadata in the existing `MediaInfoPanel` and any encoded
  orientation applied through app.scope.image.011.
- Related: app.scope.image.011, app.scope.image.013, app.scope.image.014

### app.scope.image.011 — Apply encoded image orientation exactly once

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-11 22:34 — Separate orientation normalization from ICC and XMP inspection.
- Evidence: `loadImageViewerContent` decodes the movie and reports EXIF properties through
  `MediaInfoData.addImageMetadata`, but does not normalize the encoded orientation. Temporary
  rotate/mirror commands operate on the view independently.
- Next: expose a normalized source orientation and apply it exactly once during loading,
  preserving the authored metadata and the coordinate mapping owned by app.scope.image.004.
- Complete when: all eight EXIF orientations display correctly without double rotation, reset
  returns to the oriented source, and metadata still identifies the encoded value.
- Related: app.scope.image.004, app.scope.image.013, app.scope.image.014

### app.scope.image.013 — Embedded ICC profiles have no readable identity

- Recorded: 2026-09-11 22:34
- Evidence: split from app.scope.image.011. `MediaInfoData.addImageMetadata` interprets EXIF
  and PNG text; ICC records receive only an opaque byte-count description.
- Next: expose bounded profile identity and descriptive fields, distinguishing embedded data
  from the display conversion that app.scope.image.003 owns.
- Complete when: supported profile names and source color-space identities are visible,
  malformed profiles report their limitation, and inspection does not imply an applied conversion.
- Related: app.scope.image.003, std.pixel.image.019

### app.scope.image.014 — XMP image properties remain opaque

- Recorded: 2026-09-11 22:34
- Evidence: split from app.scope.image.011. The metadata panel does not interpret image XMP
  packets; the separate InDesign preview reader does not provide an image metadata contract.
- Next: parse a bounded set of XMP descriptive properties with namespace-aware field identity,
  preserving unrecognized packets and source provenance.
- Complete when: supported XMP fields are readable and copyable, conflicting EXIF/XMP values
  remain distinguishable, and malformed or oversized packets fail within explicit limits.

### app.scope.image.007 — Animated images have no frame-step, speed, or disposal inspection

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-10 19:05 — Retain frame inspection and speed controls after shared cycle continuation was fixed
- Evidence: GIF, APNG, and WebP playback share play/pause, a frame slider, and frame count. The
  shared playback mode now stops after a cycle, repeats, or continues through the folder, with
  manual seeking kept separate from cycle completion. Previous/next-frame commands, exact frame
  delay, playback speed, disposal/blend metadata, composited-versus-raw frame view, and dropped-frame
  indicators remain absent.
- Next: expose animation frame metadata and complete the transport around the existing cached movie.
- Complete when: frame stepping is exact, delay and timestamp are visible, 0.25x–4x rates
  are covered together with the existing loop policy, raw and composited frames can be compared,
  and invalid timing/disposal warns.

### app.scope.image.003 — Color management and HDR state are invisible to the reader

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-06 07:51 — git: prompt 6
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

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-06 07:51 — git: prompt 6
- Evidence: the viewer has a complete non-destructive dihedral view transform and its information
  panel reports EXIF orientation, but there is no normalized orientation value. Coordinate consumers have no
  shared source-to-display coordinate contract.
- Next: expose normalized source orientation through app.scope.image.011, then define one coordinate mapping for
  image dimensions, pan, selection, probes, animation frames, and the products in app.scope.image.009.
- Complete when: source orientation and temporary orientation are stated separately; every image
  coordinate consumer agrees with the displayed transform; raw export keeps source bytes; and
  rendered export declares the applied orientation.
- Related: app.scope.image.011

### app.scope.image.008 — The image-set selector has no item descriptions or thumbnails

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-06 07:51 — git: prompt 6
- Evidence: `ImageViewer` now browses every indexed format through `Movie` and a shared slider;
  `viewer.imageset.test.swg` covers all nine multi-image codec paths, including unequal dimensions.
  The slider and counter do not show the selected item's kind, name, dimensions, mip/layer/face
  coordinates, or thumbnail, although `ImageFrameInfo` already supplies the indexed properties.
- Next: present those properties and lazy thumbnails in a collection selector over the existing
  reader, keeping animation playback distinct from independent-image selection.
- Complete when: item identity survives view changes and the selector shows each item's description,
  dimensions, thumbnail, and format-specific relationships without decoding the whole collection.

### app.scope.image.010 — Huge and damaged images cannot degrade progressively

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-06 07:51 — git: prompt 6
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

### app.scope.image.001 — The image has no pixel probe or measurement tools

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: zoom and pan never expose image coordinates, RGBA/channel values, premultiplied versus
  straight color, palette index, physical resolution, or distance/angle between points.
- Next: add a pointer/caret pixel inspector over decoded image coordinates, followed by a
  non-destructive line/rectangle measurement overlay.
- Complete when: coordinates and exact stored/converted channel values are copyable, alpha and
  out-of-bounds states are explicit, keyboard movement reaches individual pixels at high zoom, and
  distance/size can be reported in pixels and physical units when resolution metadata exists.

### app.scope.image.002 — Image analysis has no histogram, channel, clipping, or transparency views

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: the viewer renders the composite only. It cannot isolate R/G/B/A or luminance, show
  per-channel histograms, mark clipped shadows/highlights, visualize alpha, or inspect indexed
  palettes.
- Next: compute cancellable bounded histograms and add temporary channel/transparency overlays.
- Complete when: histogram scope states whole image or selection, high-bit-depth data is binned
  without forced 8-bit loss, channels and alpha can be inspected independently, clipping thresholds
  are configurable, and palette entries link to image pixels.

### app.scope.image.005 — Zoom lacks navigator, numeric entry, interpolation choice, and comparison scale

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
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

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: sibling navigation replaces the current image. There is no synchronized pair, flicker,
  opacity wipe, difference/heat map, alignment, or per-pixel delta readout.
- Next: build a two-image comparison surface on app.scope.001 with synchronized transform and an explicit
  alignment anchor.
- Complete when: side-by-side, overlay, flicker, absolute difference, and heat-map modes work;
  pan/zoom can synchronize; size/color-space mismatches are stated; and the pixel probe reports
  both values plus delta.
- Related: app.scope.001

### app.scope.image.009 — The displayed image cannot be copied or exported with an explicit transformation policy

- Recorded: 2026-08-29 08:36
- Updated: 2026-09-01 08:37 — git: Add backlogs for std.pixel, std.truetype, and std.win32 modules
- Evidence: there is no Copy Image, Copy Pixel Value, Copy View, Save Decoded As, or Save Frame
  command. A reader cannot tell whether orientation, color conversion, alpha, animation compositing,
  or zoom would affect output.
- Next: define raw, decoded-source, and rendered-view interchange products and expose only the forms
  the codec/pixel stack can produce faithfully.
- Complete when: clipboard and export name dimensions, pixel format, orientation, color space,
  alpha, and frame/page; raw extraction never transcodes; rendered output declares conversions;
  and large exports are cancellable.
