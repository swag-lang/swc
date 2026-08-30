# Bin API review ledger

This ledger applies the rules in `design-swag-bin-modules`. A checked family has
had its declarations, behavior, tests, examples, generated documentation, and
direct consumers reviewed together.

## Runtime

- [ ] allocation and scratch allocation
- [ ] errors, printing, and operating-system boundary
- [ ] runtime API and core primitives

## Std.Core

- [x] algorithms
- [x] collections
- [x] compression streams and codecs
- [x] hashes and checksums
- [x] diagnostics and logging
- [x] files, directories, paths, and byte/text streams
- [x] globalization
- [x] input
- [x] mathematics
- [x] memory
- [x] random generation and noise
- [x] reflection
- [x] serialization
- [x] slice algorithms
- [x] environment, process, hardware, and identifiers
- [x] text parsing, tokenization, regular expressions, and builders
- [x] jobs and threading
- [x] time and dates

## Std.TrueType

- [x] face lifecycle, sizing, and charmaps
- [x] glyph loading, outlines, rasterization, and bitmaps
- [x] SDF/MSDF generation and geometry

## Std.Pixel

- [x] color, pixel formats, images, and ownership
- [x] image decoding and encoding
- [x] transforms and filters
- [x] paths, polygons, curves, and SVG
- [x] brushes, pens, textures, painters, and layers
- [x] font loading, shaping, layout, and drawing
- [x] tests, examples, and generated documentation

## Std.Gui

- [x] application lifecycle, modal loops, hotkeys, and state persistence
- [x] surfaces, ownership, top-most state, tray icons, and command routing
- [x] base windows, parent/surface invariants, visibility, z-order, and events
- [x] frame, scroll, grid, stack, wrap, and splitter layouts
- [x] clipboard and undo
- [x] sliders and circular controls
- [x] check, radio, toggle, progress, combo, popup-list, header, and tab controls
- [x] display, editing, color-selection, and button widgets
- [x] list, tree, menu, file-browser, breadcrumb, and remaining composite controls
- [x] dialogs
- [x] rich text and editing
- [x] properties and data binding
- [x] headless testing surface and generated documentation

## Other standard modules

- [x] audio product API
- [x] OpenGL product wrapper
- [ ] Win32, GDI32, GDI+, XAudio2, and XInput native bindings

## Applications and examples

- [x] Swag Capture consumer migration
- [x] standard examples and scripts consumer migration
- [ ] final repository-wide obsolete-name and documentation scan
