# Swag Scope Image Viewer Backlog

The current viewer already navigates sibling images, pans, zooms, fits, shows actual pixels,
rotates in either direction, mirrors either axis, resets its temporary transform, and presents
GIF, APNG, and WebP animations on a timeline. The same selector browses TIFF pages, ICO variants,
PSD layers, texture subresources, and OpenEXR parts. This backlog owns professional inspection around the codecs;
missing codec and pixel-format work remains in [std.pixel.image.md](std.pixel.image.md), while
render primitives remain in [std.pixel.md](std.pixel.md).

### app.scope.image.012 — Camera RAW files show nothing

- Evidence: [File Viewer Plus 7](https://fileviewerplus.com/support/supported_file_formats)
  lists camera RAW formats including CR2, NEF, ARW and DNG.
- Next: use licensed CR2, NEF, ARW and DNG fixtures carrying JPEG previews. Read those
  previews through bounded container ranges and distinguish missing or unsupported previews.
- Done when: the embedded preview of the common TIFF-based RAW containers is extracted and
  displayed, with its source and preview metadata in the existing `MediaInfoPanel` and any encoded
  orientation applied during load.
### app.scope.image.007 — Animated images have no frame-step, speed, or disposal inspection

- Evidence: GIF, APNG, and WebP playback share play/pause, a frame slider, and frame count. The
  shared playback mode now stops after a cycle, repeats, or continues through the folder, with
  manual seeking kept separate from cycle completion. Ctrl+Page Up and Page Down step one frame,
  named Previous and Next Frame in the lens for an animation, and a paused animation's summary
  gives the delay of the frame in view, the encoded one or the default the movie plays it at.
  Timestamps, playback speed, disposal/blend metadata, composited-versus-raw frame view, and
  dropped-frame indicators remain absent.
- Next: expose animation frame metadata and complete the transport around the existing cached movie.
- Done when: timestamps are visible, 0.25x–4x rates work with the existing loop policy, raw and
  composited frames can be compared, and invalid timing/disposal warns.

### app.scope.image.003 — Color management and HDR state are invisible to the reader

- Evidence: the image information panel now inspects WebP ICC and sequenced JPEG ICC profiles for
  their source color space, PCS, and supported `desc`/`mluc` identity, explicitly without implying
  conversion. std.pixel.001/std.pixel.image.019 still record that the pixel stack has no color
  conversion pipeline; transfer function, primaries, display target, and out-of-gamut/clipping status
  are not interpreted.
- Next: define the viewer information and soft-proof controls now, then connect them to the pixel
  color pipeline as it lands.
- Done when: source and display color spaces are named, embedded profiles can be inspected,
  untagged assumptions are explicit, color conversion can be toggled for diagnosis, HDR content
  has a declared tone-map/output path, and screenshots never silently redefine source values.
- Related: std.pixel.001, std.pixel.image.019, std.pixel.002, std.pixel.003

### app.scope.image.004 — Source orientation is not distinguished from the temporary view transform

- Evidence: the viewer has a complete non-destructive dihedral view transform and its information
  panel reports EXIF orientation, but there is no normalized orientation value. Coordinate consumers have no
  shared source-to-display coordinate contract.
- Next: define one coordinate mapping for image dimensions, pan, selection, probes, animation
  frames, and the products in app.scope.image.009, with normalized source orientation applied
  during loading.
- Done when: source orientation and temporary orientation are stated separately; every image
  coordinate consumer agrees with the displayed transform; raw export keeps source bytes; and
  rendered export declares the applied orientation.
- Related: app.scope.image.009

### app.scope.image.010 — Huge and damaged images cannot degrade progressively

- Evidence: `Movie.maxCacheBytes` now bounds cached frames to 64 MiB by default and `DecodeOptions`
  bounds input, frame count, and per-image storage. The background loader still publishes its first
  image only after a complete decode and cache preparation; no partial image or region reaches the
  viewer while slow storage or decoding is in progress.
- Next: connect progressive or region decoding to background publication, beginning with one large
  raster format and retaining the existing cache ceilings.
- Done when: metadata and a bounded preview appear before full decode where possible, visible
  tiles have priority, cancellation is prompt, and partial damage is marked without discarding valid
  regions.
- Related: app.scope.viewers.004, std.pixel.image.038, std.pixel.image.039

### app.scope.image.001 — The pixel probe cannot be copied, stepped or measured with

- Evidence: the pointer over a picture reads its pixel (counted in the stored picture through
  zoom, pan, rotation and mirror, `ImageView.pixelAt`) and its straight 8-bit color and opacity
  into the information band. The color of the pixel read last can be copied as `#RRGGBB`, or
  `#RRGGBBAA` when it is not opaque, from the lens, which names it and where it is, or with
  Ctrl+Shift+C. Stored channel depth, premultiplied versus straight values, palette index,
  physical resolution, keyboard stepping between pixels, a copy of the whole reading, and distance
  or angle between points are absent.
- Next: let the keyboard move a probe one pixel at a time at high zoom and copy its reading, then
  add a non-destructive line/rectangle measurement overlay.
- Done when: stored and converted channel values are distinguished, alpha and out-of-bounds states
  are explicit, keyboard movement reaches individual pixels at high zoom, and distance/size can be
  reported in pixels and physical units when resolution metadata exists.

### app.scope.image.002 — Image analysis has no histogram, channel, clipping, or transparency views

- Evidence: the viewer renders the composite only. For a still picture with 8-bit alpha, the
  information sheet says whether the alpha hides anything: none of it, or the share of pixels it
  makes wholly transparent and the share it lets show through. It cannot isolate R/G/B/A or
  luminance, show per-channel histograms, mark clipped shadows/highlights, visualize alpha, or
  inspect indexed palettes.
- Next: compute cancellable bounded histograms and add temporary channel/transparency overlays.
- Done when: histogram scope states whole image or selection, high-bit-depth data is binned
  without forced 8-bit loss, channels and alpha can be inspected independently, clipping thresholds
  are configurable, and palette entries link to image pixels.

### app.scope.image.005 — Zoom lacks navigator, numeric entry, interpolation choice, and comparison scale

- Evidence: the information band now exposes a clickable percentage with common presets, actual
  size, and fit. There is no arbitrary numeric entry, fit-width/height, overview navigator,
  pixel-grid threshold, nearest-versus-smooth sampling control, or lockable scale across sibling
  images.
- Next: add arbitrary numeric entry, a small optional navigator, and sampling mode to the existing
  zoom control.
- Done when: numeric zoom, Fit All/Width/Height, pixel grid, and sampling policy are explicit;
  the navigator shows and moves the viewport; and next/previous can preserve zoom and image-center
  coordinates when requested.

### app.scope.image.006 — Images cannot be compared side by side, overlaid, or by difference

- Evidence: sibling navigation replaces the current image. There is no synchronized pair, flicker,
  opacity wipe, difference/heat map, alignment, or per-pixel delta readout.
- Next: build a two-image comparison surface with synchronized transform and an explicit
  alignment anchor, reusing app.scope.003's paired presentation and app.scope.image.001's probe.
- Done when: side-by-side, overlay, flicker, absolute difference, and heat-map modes work;
  pan/zoom can synchronize; size/color-space mismatches are stated; and the pixel probe reports
  both values plus delta.
- Related: app.scope.003, app.scope.image.001

### app.scope.image.009 — The displayed image cannot be copied or exported with an explicit transformation policy

- Evidence: Copy Image already copies the upright picture. Pixel and rendered-view copying,
  decoded image export and frame export remain open. The output needs clear orientation,
  color conversion, alpha and compositing rules. [File Viewer Plus 7](https://fileviewerplus.com/features)
  can export individual GIF and APNG frames.
- Next: define raw, decoded-source, and rendered-view interchange products and expose only the forms
  the codec/pixel stack can produce faithfully.
- Done when: raw extraction never transcodes, decoded-source and rendered-view outputs state their
  pixel format, orientation, color space, alpha and frame/page policy, rendered output declares
  conversions, and large exports are cancellable.
