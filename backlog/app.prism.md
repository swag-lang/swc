# app.prism

Swag Prism: editable Swag source and independent viewers of what it compiles into and what it does.

The application demonstrates its own compiler and toolkit through executable examples. A single
viewer is the default; a global comparison switch exposes a second panel. Each panel keeps its
microcode, 2D render, and GUI viewer options. The gallery supplies animated plasma, a Julia set,
a clickable GUI, and a dot product. When live editing is enabled, source edits recompile after
150 ms of inactivity.

Native previews run in separate, cancellable processes and exchange complete frames through a
mapped file. The GUI preview forwards clicks to real controls. Compiler and preview failures stay
in their viewer, and the readouts report measured compilation and frame rendering time.

## Entries

### app.prism.003 — Forward continuous input to the running preview

- Recorded: 2026-09-08 21:53
- Updated: 2026-09-11 22:14 — Separate input delivery from resolution negotiation and frame export.
- Evidence: `previewcanvas.swg` forwards clicks; `FrameHeader` has one acknowledged click mailbox
  and `previewhost.swg` calls `HeadlessHost.click`. Keyboard, pointer movement, drag and wheel
  events have no transport. Existing native preview tests cover clicks, pause, recovery and cancellation.
- Next: add a bounded ordered event queue with focus and cancellation rules, then route keyboard,
  movement, button transitions and wheel events to the child controls.
- Complete when: event order and coordinates survive fitted previews, dragging and key sequences
  work, replacing a preview clears pending input, and saturation has an explicit policy.
- Related: app.prism.006

### app.prism.004 — Inspect a library function from Prism

- Recorded: 2026-09-08 21:53
- Updated: 2026-09-11 22:14 — Move the compiler selector into its owning domain; retain the Prism workflow.
- Evidence: `MicrocodeViewer` builds a source snippet through `BuildRequest`. It has no library
  symbol request or symbol selector. The compiler flag needed to inspect unedited source is
  compiler.core.040, split from this entry.
- Next: carry library/workspace identity, symbol pattern and requested stage in the build request,
  then connect the compiler selector without modifying library files.
- Complete when: selecting a library function displays its requested microcode stage, ambiguous
  or absent matches are explained, and the library working tree remains unchanged.
- Related: compiler.core.040, app.prism.002

### app.prism.006 — Negotiate preview resolution with the panel

- Recorded: 2026-09-11 22:14
- Evidence: split from app.prism.003. `FrameChannel` fixes frames at 640 by 400 pixels;
  `PreviewCanvas` scales that image into the panel and the child sets up a fixed-size host.
- Next: version the frame transport to negotiate dimensions and DPI with bounded allocation and
  an acknowledgement before either side changes the shared buffer layout.
- Complete when: resizing and DPI changes produce correctly sized frames, input coordinates stay
  aligned, allocation remains bounded, and cancellation cannot race a buffer replacement.
- Related: app.prism.003

### app.prism.007 — Save a completed preview frame as a golden candidate

- Recorded: 2026-09-11 22:14
- Evidence: split from app.prism.003. `PreviewViewer` receives complete BGRA images, but its
  commands cannot export the displayed frame; test goldens are authored through separate tests.
- Next: export one acknowledged frame with source/build/options and dimensions as provenance,
  leaving golden acceptance to the existing review workflow.
- Complete when: the saved image is a complete frame, reproducing its source and options is
  possible, export cannot race frame publication, and existing golden files are not overwritten
  without an explicit destination choice.

### app.prism.002 — Read the pipeline instead of printing it

- Recorded: 2026-09-08 21:53
- Updated: 2026-09-09 08:31 — Correct the baseline: terminal colors are already preserved.

The output pane retains the compiler's terminal colors while displaying plain selectable text. The compiler knows
much more than that text: `MicroPassManager` prints a header naming the stage, the optimization
level, and the instruction count before and after with the gain it produced, and it colors every
token by a `SyntaxColor` category that separates a physical register from a virtual one.

Parsing that header turns the pane into the view the application is for: a frieze of the stages
with the instruction count under each, a mark on the passes that changed the function and on those
that left it alone, and a diff between the two sides of one pass. `SyntaxColorMode::ForDoc` already
emits the same categories as tags rather than as escapes, which is the stream to read.

Next: parse the `[micro]` header and instruction block, map the categories onto the theme palette,
and show the count and the gain beside the stage selector.
