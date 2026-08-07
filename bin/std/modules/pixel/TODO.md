# Pixel Roadmap

This file is the roadmap for `std/pixel`, measured against the 2D graphics libraries it competes
with: Skia, Cairo, Blend2D, NanoVG, ThorVG, and Direct2D — plus stb_image and libvips on the
imaging side.

It is not the repository's discovery backlog. Defects and leads about other subsystems belong in
[FINDINGS.md](../../../../FINDINGS.md); compiler and language intent belongs in the root
[TODO.md](../../../../TODO.md). This file holds intent about this module.

Entries are ordered by decreasing value, not by decreasing effort. An entry disappears when it
ships; history lives in git, not here.

## Where the module already stands

This is the strongest module in the tree, and several parts of it are ahead of the field.

- **Codecs**: eight decoders and eight encoders — BMP, GIF, ICO, JPEG including progressive, PNG,
  TGA, TIFF, WebP with both the lossless and VP8 paths. Round-tripping eight formats is more than
  stb offers and more than most graphics libraries carry at all.
- **Computational geometry**: `poly/` has boolean path operations, path offsetting, and Delaunay
  triangulation. Skia exposes far less of this and Cairo none.
- **Math typesetting**: `math/mathexpression.swg` and `math/mathlayout.swg` implement TeX-style
  formula layout with display, text, script and script-script styles. No competing 2D library has
  this. It is a real differentiator and nothing on this list should put it at risk.
- **Distance-field text** through the `truetype` MSDF path, which is what GPU text actually wants.
- **Imaging**: thirteen filters and eleven transforms, including content-aware `smartcrop` and Haar
  feature statistics.
- **Painter**: a full state stack, transform stack, clipping rectangles *and* clipping regions with
  set operations, render targets, custom shaders, layers, and integrated DPI content scale.
- Two backends behind one API — CPU and OpenGL — with command-stream golden regression tests.

The gaps are in composition fidelity, color, and the GPU backend.

---

## Tier A — Composition fidelity

### 1. Seven blend modes, and the useful ones are missing

- Problem: `BlendingMode` in `src/painter/painter.swg` is `Copy`, `Alpha`, `Add`, `Sub`, `SubDst`,
  `Min` and `Max`. The separable blend modes that PDF, SVG, CSS, Skia and every design tool define
  are absent — Multiply, Screen, Overlay, Darken, Lighten, ColorDodge, ColorBurn, HardLight,
  SoftLight, Difference and Exclusion — as are the non-separable Hue, Saturation, Color and
  Luminosity.
- Consequence: Multiply and Screen alone account for most real compositing work. Without them,
  shadow, tint, highlight and any layered design effect cannot be expressed. It is also what
  blocks `sCapture` roadmap entry 3, which asks for capture-level effects.
- Fix: the separable set first — they are a per-channel function and cheap in both backends. The
  four non-separable modes need the full colour computation and can follow.
- This is the highest value-to-effort entry in the module.

### 2. No image filter graph

- Problem: blur exists only as a painter shader (`setBlurShader`), applied to what is being drawn.
  There is no composable effect applied to a rendered result: no drop shadow, no colour matrix, no
  blur-as-an-effect, no chained filters.
- Consequence: the standard way to build a shadow, a glow, a duotone, or a saturation adjustment
  over arbitrary content is unavailable. `image/filter/` operates on an `Image` in memory, which is
  not the same tool.
- Fix: an effect graph over render targets, with `SkImageFilter` as the model — a small set of
  primitives (blur, offset, colour matrix, blend, merge) that compose. Depends on entry 1 for the
  blend node.
- Downstream: this is what `sCapture` needs for border, drop shadow, torn edge and perspective.

### 3. Gradients cap at eight stops, and SVG cannot read them at all

Two separate problems in the same feature.

- `MaxGradientStops = 8` in `src/types/brush.swg`. Design tools and SVG routinely produce more, and
  a gradient silently loses its later stops.
- `src/svg/svgparse.swg` parses `svg`, `g`, `defs`, `use`, `path`, `rect`, `circle`, `ellipse`,
  `line`, `polygon`, `polyline` and `style`. It does not parse `linearGradient`, `radialGradient`
  or `stop` — so **an SVG with a gradient renders flat**, even though `Brush` supports linear,
  radial and sweep gradients natively. The capability exists on both sides and nothing connects
  them.
- Also unparsed: `text`, `tspan`, `image`, `clipPath`, `mask`, `pattern`, `marker`, `symbol`,
  `filter`, and the `stroke-dasharray` attribute. `fill-opacity`, `stroke-opacity` and `opacity`
  ARE parsed (`applyStyleProperty` in `svgparse.swg`), which is what the drop-shadow tile of the
  theme atlas is built out of.
- This constrains the repository directly: the GUI theme is vector — `gui/src/theme/widgets.svg`
  and `icons.svg` — so the parser's coverage is the theme's design vocabulary.

---

## Tier B — Colour and precision

### 4. Eight bits per channel, and nothing else

- `PixelFormat` is `BGR8`, `BGRA8`, `RGB8`, `RGBA8`. There is no 16-bit format, no half or full
  float, no single-channel grayscale, and no declared premultiplied variant.
- Consequence: no HDR imaging, no high-precision intermediate for a filter chain, and no headroom
  in the render targets that entry 2 would introduce. A multi-stage effect graph quantising to
  eight bits at every step is where banding comes from.
- A single-channel format is also the natural storage for masks and distance fields, both of which
  the module already produces.

### 5. No colour management

- Nothing in the API distinguishes sRGB from linear, there is no ICC profile handling, no wide
  gamut such as Display P3, and no HDR output path.
- The consequence is not only missing features. Compositing non-linear sRGB values directly is the
  standard cause of gradients and antialiased edges reading darker than they should — so this is a
  fidelity question, not a checkbox. Skia and Direct2D both take a position on it; this module
  takes none, which means the caller cannot take one either.
- Fix: decide the working space explicitly and say so in the API, then let a surface declare its
  own. Depends on entry 4 for anywhere the working space needs more than eight bits.

---

## Tier C — Reach

### 6. OpenGL is the only GPU backend

- `render/` has `cpu` and `ogl`. There is no Vulkan, Direct3D, Metal or WebGPU path.
- On Windows this is the weakest choice available: OpenGL driver quality varies widely, and some
  ARM devices have no usable implementation at all. Skia ships GL, Vulkan, Metal and D3D.
- This also intersects `core` roadmap entry 2. A second platform needs a second backend regardless,
  so choose the target with that in mind rather than twice.
- The backend boundary is already two implementations deep, so a third is additive.

### 7. No vector output

No PDF, no SVG export, no PostScript. Cairo and Skia both write PDF, and it is the format anything
document-shaped or printable needs. `sCapture` roadmap entry 1 asks for PDF export, and this is
where it would land.

### 8. Codec coverage

The current set already beats stb. The gaps worth considering, in order: QOI, which is trivial and
useful; AVIF and JPEG XL for modern web images; DDS and KTX2 as GPU texture containers, which
matter as soon as anything wants compressed textures; EXR for high dynamic range, which depends on
entry 4; and PSD for import.

### 9. Path effects

Dashing exists. Missing: path trimming by arc length, arc-length measurement, and corner effects.
Boolean operations already exist in `poly/`; the question is whether they are reachable from a
painter path or only from the polygon layer.

---

## Out of scope

**A scene graph or a retained-mode API.** `pixel` is an immediate-mode painter plus an imaging
library, and `gui` owns the retained tree above it. Do not grow a second one here.

**Video decoding.** The WebP VP8 decoder exists because WebP needs it, not as the beginning of a
media stack. If `sCapture` ever records video, that belongs in its own module.
