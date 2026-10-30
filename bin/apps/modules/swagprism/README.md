# Swag Prism

Edit Swag source and see what the compiler makes of it. The window is two quiet columns separated by
one hairline: the source at the left, a result at the right. Quiet text menus above each column
carry its settings — the example the source started from; the viewer, the stage and the O0/O1/O2
optimization level of the result. Everything else is in the lens, which `Ctrl Space` opens:
every command, the examples, the views, the stages, the levels, the presets,
the theme, the language and About. The readings of the build are in the sheet (`Ctrl I`, or `I`
where nothing types). The foot of the window keeps a hint line at the left and the reading of the
last build at the right.

- **2D render:** define `func shade(x, y, time: f32)->u32`. The viewer runs native code for each
  pixel of a 640 by 400 image. Coordinates span approximately `[-1.6, 1.6]` horizontally and
  `[-1, 1]` vertically. Return an ARGB color. Rows run in parallel on the runtime's worker pool. Animation
  uses elapsed time; `shade` must support concurrent calls (avoid unsynchronized writes to shared state).
- **GUI:** define `func buildView(parent: *Gui.Wnd)`. Build controls under the supplied parent;
  the viewer displays the actual GUI and forwards clicks into it. The current preview supports
  clicks; keyboard input, dragging, and the wheel remain future work.
- **Microcode:** inspect the first function that starts a line with `func`. One compilation prints
  it at every offered stage, so choosing a stage compiles nothing. The listing writes each
  instruction as a reader writes it, or as the backend spells it (Show Opcodes), with the source
  lines on request (Show Source Lines), in the compiler's colors; `Ctrl C` copies the chosen rows.

Three views share the window (`Ctrl 1`, `Ctrl 2`, `Ctrl 3`):

- **Source and Result**, the default.
- **Stage by Stage**: a frieze of the steps that changed the function, browsed with `←` `→`. The
  margin reads what the chosen step did to the count, and its listing strikes out the instructions
  the pass removed and marks the ones it added in Arc; Show the Change turns the marks off.
- **Compare Two Builds**: the reference build at the left, the main build at the right, each headed
  by its count; the main build says what it gains, and both mark their innermost loop.

The example menu replaces the source with a plasma, Julia fractal, live GUI, or dot product and
selects the corresponding viewer. `Ctrl ⏎` compiles the source for the visible builds. Automatic
compilation waits 150 ms after the last edit; the switch under a running picture, or Recompile
After Editing in the lens, turns it off.

Format Source (`Ctrl Shift F`) runs the Swag formatter and applies the result as one undoable edit.
A syntax error or a newer edit leaves the source unchanged, and the sheet shows the formatter's
diagnostics.

Build Configuration, in the lens, takes the place of a viewer with a Swag configuration editor.
Choose a `release` or `devmode` preset from its header, then edit a `#run` block using
`unwrap Swag.compiler().getBuildCfg()`, as in `module.swg`.
The starter fragment includes commented examples for safety, sanity, inlining, vectorization, and
floating-point options. Restore Defaults restores that build's preset, configuration text, and original
optimization level. Configuration belongs to the build and survives changing viewer type. Prism
sets the required backend kind and dependency publication after the custom configuration. Presets
apply their option values in `module.swg`, so an explicit CLI preset cannot overwrite your edits.
The compiler configuration name used by `#cfg` remains its implicit `devmode`; the O0/O1/O2 menu
supplies the initial optimization level, which the configuration fragment may override.

Frames travel directly through shared memory. The interface checks for a new frame every 16 ms;
an event wakes the producer as soon as a frame is consumed, without a fixed sleep after rendering. Only the first frame changes the layout,
and timing readings refresh periodically instead of on every frame.

A running picture has a quiet Pause or Resume in its column header; microcode has none. The reading
shows whether the build was reused, or measured build time in milliseconds and frame computation
time in microseconds; this is not a frames-per-second benchmark. Hidden previews stop consuming frames until shown again.

Prism finds the compiler beside the installed application, or by walking up from its development
output. The default snippet options apply release settings during module setup. Allocator
capabilities still follow the compiler's initial devmode configuration; selecting complete preview
runtime variants is tracked in [app.prism.008](../../../../backlog/app.prism.md#appprism008--select-allocator-capabilities-with-the-preview-host).
Microcode alone imports Core; 2D execution imports Pixel;
GUI execution imports Gui. Microcode beside an execution viewer uses that viewer's module contract.
Native snippets compile into a shared library containing the edited code and its entry wrapper.
The renderer is already compiled into Prism and runs in a separate host process, so edits do not
recompile frame transport, the pixel loop, or GUI hosting. Prism explicitly links its imports as
shared libraries to share the runtime and allocator with those loaded modules. Preview builds
publish their runtime dependencies. The window shares a bounded compilation cache
across its panels. Matching source, configuration, and viewer contract reuse the same artifact,
including a build already in progress. A native viewer and microcode can share one native build when
their source and settings match. Different optimization levels or configuration overrides require
separate builds. Compile explicitly rebuilds; automatic edits and option changes can reuse results.
Each execution viewer has its own process, frame channel, pause state, and GUI input. The current animation continues while a replacement compiles and starts. Only the replacement's
first complete frame switches the displayed process; old processes are reaped off the UI thread.
Further edits cancel obsolete replacements. A paused viewer displays one new frame after a
successful edit and stays paused. A failed replacement shows diagnostics while retaining the last
working process. An unchanged preview continues playing when another panel changes. Snippets execute in a separate process;
switching examples, closing a viewer, or quitting cancels and reaps its process. A build
has a 60-second deadline, and an unresponsive preview has a 10-second frame deadline.

For a development compiler, pass `--run-arg=--compiler=<absolute compiler path>` to select the
compiler used by snippets and formatting. `--run-arg=--compiler-workers=6` limits those child
compilers too; the outer `--num-cores` option only bounds the compiler building Prism. Positive
worker limits are explicit development overrides. Without one, the child compiler chooses its own
worker budget; Prism imposes no fixed ceiling. Preview hosts likewise use the runtime's automatic pool.

From the repository root:

```powershell
tools\apps.bat dm run swagprism --run-arg=--compiler-workers=6
tools\apps.bat dm test swagprism --run-arg=--compiler-workers=6
tools\apps.bat dm smoke swagprism --run-arg=--compiler-workers=6
```
