# Swag Prism

Edit Swag source and explore it through independently configured viewers. Prism opens with one
animated 2D viewer. The framed icon at the right of the viewer header toggles a second panel; each
panel's header groups its viewer selector and O0/O1/O2 optimization level. Changing the viewer
keeps the panel's optimization level and restores that viewer's stage or playback state.

- **2D render:** define `func shade(x, y, time: f32)->u32`. The viewer runs native code for each
  pixel of a 640 by 400 image. Coordinates span approximately `[-1.6, 1.6]` horizontally and
  `[-1, 1]` vertically. Return an ARGB color. Rows run in parallel on up to six workers. Animation
  uses elapsed time; `shade` must support concurrent calls (avoid unsynchronized writes to shared state).
- **GUI:** define `func buildView(parent: *Gui.Wnd)`. Build controls under the supplied parent;
  the viewer displays the actual GUI and forwards clicks into it. The current preview supports
  clicks; keyboard input, dragging, and the wheel remain future work.
- **Microcode:** inspect the first function that starts a line with `func`. Choose a compilation
  stage and O0, O1, or O2. Compiler output retains its colors and remains selectable.

The example combo replaces the source with a plasma, Julia fractal, live GUI, or dot product and
selects the corresponding viewer in the first panel. Compile feeds the same source to both
visible panels. The source panel toolbar keeps Compile, Format, Auto, and the examples on one line;
labels yield to icons when the source panel narrows. Automatic
compilation waits 150 ms after the last edit and can be disabled.

Format runs the Swag formatter on the source and applies the result as one undoable edit. A syntax
error or a newer edit leaves the source unchanged. Compilation progress appears only in the bottom
information bar, with an animated spinner.

The settings icon in each viewer header opens a Swag configuration editor. Choose a `release` or
`devmode` preset, then edit a `#run` block using `Swag.compiler().getBuildCfg()!`, as in `module.swg`.
The starter fragment includes commented examples for safety, sanity, inlining, vectorization, and
floating-point options. The reset icon restores that panel's preset, configuration text, and original
optimization level. Configuration belongs to the panel and survives changing viewer type. Prism
sets the required backend kind and dependency publication after the custom configuration. Presets
apply their option values in `module.swg`, so an explicit CLI preset cannot overwrite your edits.
The compiler configuration name used by `#cfg` remains its implicit `devmode`; the O0/O1/O2 selector
supplies the initial optimization level, which the configuration fragment may override.

Frames travel directly through shared memory. The interface checks for a new frame every 16 ms;
an event wakes the producer as soon as a frame is consumed, without a fixed sleep after rendering. Only the first frame changes the panel layout,
and timing labels refresh periodically instead of on every frame.

Execution previews have a Pause/Resume icon in their panel header; microcode has no playback button.
The icon stays pressed while paused and restores the selected viewer's playback state. Their status
shows whether the build was reused, or measured build time in milliseconds and frame computation
time in microseconds; this is not a frames-per-second benchmark. Hidden previews stop consuming frames until shown again.

Prism finds the compiler beside the installed application, or by walking up from its development
output. The default options match release. Microcode alone imports Core; 2D execution imports Pixel;
GUI execution imports Gui. Microcode beside an execution viewer uses that viewer's module contract.
Native snippets compile into a shared library containing the edited code and its entry wrapper.
The renderer is already compiled into Prism and runs in a separate host process, so edits do not
recompile frame transport, the pixel loop, or GUI hosting. Prism explicitly links its imports as
shared libraries to share the runtime and allocator with those loaded modules. Preview builds
publish their runtime dependencies. The window shares a bounded compilation cache
across its panels. Matching source, configuration, viewer contract, and stage reuse the same artifact,
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

From the repository root:

```powershell
bin\swc.dm.exe --num-cores 6 tools\apps.swgs dm run swagprism --num-cores 6
bin\swc.dm.exe --num-cores 6 tools\apps.swgs dm test swagprism --num-cores 6
bin\swc.dm.exe --num-cores 6 tools\apps.swgs dm smoke swagprism --num-cores 6
```
