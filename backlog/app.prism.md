# app.prism

The Swag Prism application: a snippet on the left, what the compiler made of it on the right.

The application exists to answer the one objection a new language cannot answer with prose — that
its backend is somebody else's work, that its compile-time execution is a slide, that its safety
rules are decoration. It answers by showing the compiler working, in a window built out of the
language the compiler compiles.

What already stands: the window, the editor with the Swag lexer, the pipeline-stage selector, and
the probe that compiles a snippet in a temporary module through a separate compiler process and
shows what `Swag.PrintMicro` printed for the chosen stage.

## Entries

### app.prism.004 — Inspect a function of `bin/std` without editing its source

- Recorded: 2026-09-08 21:53

`Swag.PrintMicro` is an attribute, so asking for a stage means writing it into the source. That is
right for a snippet the reader owns and wrong for `Core.Array.add`: a tool must not edit the
standard library to look at it.

`CodeGen::startFunction` already holds the fully scoped name one line below where it installs the
print options — see the `setPrintPassOptions` and `setPrintLocation` pair in
`src/Compiler/CodeGen/Core/CodeGen.cpp`. A command-line selector matching that name and appending
its stages to the attribute's own list is the whole change; nothing else in the pipeline moves.

Next: add `--print-micro=<symbol pattern>:<stage>` to the compiler, then let Swag Prism take a
symbol as well as a snippet. That turns the pane from a sandbox for the reader's own code into a
readable machine-level view of the library, which is the better argument of the two.

### app.prism.003 — Host a running program in a result pane

- Recorded: 2026-09-08 21:53

The pipeline pane shows what the compiler made of the snippet. It does not show what the snippet
does, and a prototype of a drawing or of an interface is judged by what it draws.

`Gui.Testing.HeadlessHost` is the engine this needs: it builds a real application, theme, surface,
and window tree and renders them into an image with no desktop under it, and it already carries a
simulated pointer, timers, and modal handling. It was written to freeze time for tests, so a
preview host sets `setMotionPreference` and `deterministicStreaming` the other way.

The snippet must not run in the application's process: a fault in a prototype has to cost the
result pane and never the text the reader was writing. A long-lived child holding the host, taking
input events over a pipe and returning frames, gives crash isolation and an interactive preview
between compilations rather than a picture that refreshes.

Next: pixel mode first — the snippet fills an `Image`, the child returns it, the pane shows it.
Window mode, input forwarding, and "save this frame as a golden" follow on the same transport.

### app.prism.002 — Read the pipeline instead of printing it

- Recorded: 2026-09-08 21:53

The output pane shows the compiler's text with its terminal escapes removed. The compiler knows
much more than that text: `MicroPassManager` prints a header naming the stage, the optimization
level, and the instruction count before and after with the gain it produced, and it colors every
token by a `SyntaxColor` category that separates a physical register from a virtual one.

Parsing that header turns the pane into the view the application is for: a frieze of the stages
with the instruction count under each, a mark on the passes that changed the function and on those
that left it alone, and a diff between the two sides of one pass. `SyntaxColorMode::ForDoc` already
emits the same categories as tags rather than as escapes, which is the stream to read.

Next: parse the `[micro]` header and instruction block, map the categories onto the theme palette,
and show the count and the gain beside the stage selector.

### app.prism.001 — Compile off the frame

- Recorded: 2026-09-08 21:53

`MainWindow.compile` runs the compiler to completion before it returns, so the window is frozen
while it does. A snippet is one small module and its build folder is reused, so the pause is short,
but it is a pause on every keystroke-driven recompilation the application wants to offer.

Next: move the compilation to a worker and deliver its result through a timer, then recompile on a
short idle after the last edit instead of on an explicit press.
