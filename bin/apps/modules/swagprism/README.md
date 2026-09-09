# Swag Prism

Edit Swag source and explore it through independently configured viewers. Prism opens with one
animated 2D viewer. The framed icon at the right of the toolbar toggles a second panel; each
panel's combo selects its viewer and keeps that viewer's options when switching away and back.

- **2D render:** define `func shade(x, y, time: f32)->u32`. The viewer runs native code for each
  pixel of a 640 by 400 image. Coordinates span approximately `[-1.6, 1.6]` horizontally and
  `[-1, 1]` vertically. Return an ARGB color. Animation time advances by 1/30 second per frame.
- **GUI:** define `func buildView(parent: *Gui.Wnd)`. Build controls under the supplied parent;
  the viewer displays the actual GUI and forwards clicks into it. The current preview supports
  clicks; keyboard input, dragging, and the wheel remain future work.
- **Microcode:** inspect the first function that starts a line with `func`. Choose a compilation
  stage and O0, O1, or O2. Compiler output retains its colors and remains selectable.

The example combo replaces the source with a plasma, Julia fractal, live GUI, or dot product and
selects the corresponding viewer in the first panel. Compile feeds the same source to both
visible panels. Automatic compilation waits 700 ms after the last edit and can be disabled.

Execution previews have their own optimization selector and Pause/Resume action. Their status
shows measured build time in milliseconds and frame computation time in microseconds; this is
not a frames-per-second benchmark. Hidden previews stop consuming frames until shown again.

Prism finds the compiler beside the installed application, or by walking up from its development
output. It builds snippets with the release program configuration and published standard GUI
dependencies. Each viewer owns a temporary module and cache. Snippets execute in a separate
process; switching examples, closing a viewer, or quitting cancels and reaps its process. A build
has a 60-second deadline, and an unresponsive preview has a 10-second frame deadline.

From the repository root:

```powershell
bin\swc.dm.exe --num-cores 6 tools\apps.swgs dm run swagprism --num-cores 6
bin\swc.dm.exe --num-cores 6 tools\apps.swgs dm test swagprism --num-cores 6
bin\swc.dm.exe --num-cores 6 tools\apps.swgs dm smoke swagprism --num-cores 6
```
