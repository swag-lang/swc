# app.prism

Swag Prism: editable Swag source and independent viewers of what it compiles into and what it does.

The application demonstrates its own compiler and toolkit through executable examples. The window
shows the source beside one result; a stage-by-stage view and a comparison of two builds take the
window on request. Each build keeps its microcode, 2D render, and GUI viewer options. The gallery supplies animated plasma, a Julia set,
a clickable GUI, and a dot product. When live editing is enabled, source edits recompile after
150 ms of inactivity.

Native previews run in separate, cancellable processes and exchange complete frames through a
mapped file. The GUI preview forwards clicks to real controls. Compiler and preview failures stay
in their viewer, and the readouts report measured compilation and frame rendering time.

## Entries

### app.prism.004 — Inspect a library function from Prism

- Evidence: `MicrocodeViewer` builds a source snippet through `BuildRequest`. It has no library
  symbol request or symbol selector. The compiler now selects unedited functions from the
  command line: `--print-micro <pattern>[:<stage>]` matches a scoped name or its trailing part,
  `*` matches any run of characters, and a pattern matching nothing prints nothing.
- Next: carry library/workspace identity, symbol pattern and requested stage in the build request,
  then pass them to the compiler as `--print-micro` without modifying library files.
- Done when: selecting a library function displays its requested microcode stage, ambiguous
  or absent matches are explained, and the library working tree remains unchanged.
- Related: app.prism.002

### app.prism.002 — Color the listing by token category instead of terminal colors

- Evidence: `Pipeline.Inspection` reads the `[micro]` printings of every offered stage from one
  compilation: the header, the instructions, labels and source lines, the steps that changed the
  function, and a before/after diff (`inspection.test.swg`). It reads the ANSI stream, so the
  listing keeps the terminal palette deepened by `Color.ensureContrast`, and `ListingView` chooses
  whole rows rather than characters. `SyntaxColorMode::ForDoc` emits token categories as tags.
- Next: read the `ForDoc` stream instead of the escapes and map its categories onto the theme's
  syntax palette; let the listing choose characters as well as rows.
- Done when: the listing's colors come from the theme in both palettes and a part of a row can be
  copied.
- Related: app.prism.004

### app.prism.003 — Forward continuous input to the running preview

- Evidence: `previewcanvas.swg` forwards clicks; `FrameHeader` has one acknowledged click mailbox
  and `previewhost.swg` calls `HeadlessHost.click`. Keyboard, pointer movement, drag and wheel
  events have no transport. Existing native preview tests cover clicks, pause, recovery and cancellation.
- Next: add a bounded ordered event queue with focus and cancellation rules, then route keyboard,
  movement, button transitions and wheel events to the child controls.
- Done when: event order and coordinates survive fitted previews, dragging and key sequences
  work, replacing a preview clears pending input, and saturation has an explicit policy.
- Related: app.prism.006

### app.prism.006 — Negotiate preview resolution with the panel

- Evidence: split from app.prism.003. `FrameChannel` fixes frames at 640 by 400 pixels;
  `PreviewCanvas` scales that image into the panel and the child sets up a fixed-size host.
- Next: version the frame transport to negotiate dimensions and DPI with bounded allocation and
  an acknowledgement before either side changes the shared buffer layout.
- Done when: resizing and DPI changes produce correctly sized frames, input coordinates stay
  aligned, allocation remains bounded, and cancellation cannot race a buffer replacement.
- Related: app.prism.003

### app.prism.007 — Save a completed preview frame as a golden candidate

- Evidence: split from app.prism.003. `PreviewViewer` receives complete BGRA images, but its
  commands cannot export the displayed frame; test goldens are authored through separate tests.
- Next: export one acknowledged frame with source/build/options and dimensions as provenance,
  leaving golden acceptance to the existing review workflow.
- Done when: the saved image is a complete frame, reproducing its source and options is
  possible, export cannot race frame publication, and existing golden files are not overwritten
  without an explicit destination choice.

### app.prism.008 — Select allocator capabilities with the preview host

- Evidence: `BuildSettings.presetSource` implements Release by editing an implicit devmode
  configuration in `#run`. This cannot remove the allocator capability tags fixed before setup.
  Native previews load shared runtime libraries into the precompiled host, so choosing tags only
  for the edited module is not a complete runtime selection.
- Next: design complete host and dependency variants for the two presets, including how panel
  changes reuse them. Establish the shared-runtime contract before changing per-preview tags.
- Done when: Release previews omit both allocator capability tags throughout their runtime,
  devmode previews include them by default, cold and warm preview builds meet the existing
  timeout, and compilation, native loading and unload tests preserve one runtime per process.
