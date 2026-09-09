# app.prism

Swag Prism: editable Swag source and independent viewers of what it compiles into and what it does.

The application demonstrates its own compiler and toolkit through executable examples. A single
viewer is the default; a global comparison switch exposes a second panel. Each panel keeps its
microcode, 2D render, and GUI viewer options. The gallery supplies animated plasma, a Julia set,
a clickable GUI, and a dot product. Source edits recompile after 700 ms of inactivity.

Native previews run in separate, cancellable processes and exchange complete frames through a
mapped file. The GUI preview forwards clicks to real controls. Compiler and preview failures stay
in their viewer, and the readouts report measured compilation and frame rendering time.

## Entries

### app.prism.003 — Extend the running-program preview

- Recorded: 2026-09-08 21:53
- Updated: 2026-09-09 08:31

The 2D and GUI viewers now build executable snippets, receive live frames, pause, cancel, and
restart after edits. The GUI child hosts real controls through `Gui.Testing.HeadlessHost`; clicks
are mapped from the fitted image back to the child's logical coordinates. These paths have native
process, interaction, recovery, cancellation, and rendered surface tests.

Next: forward keyboard input, pointer movement, drag gestures, and the wheel; negotiate rendering
resolution with the panel and DPI; add "save this frame as a golden". The first transport uses a
single acknowledged frame and click mailbox, so continuous input needs its own ordered queue.

### app.prism.002 — Read the pipeline instead of printing it

- Recorded: 2026-09-08 21:53
- Updated: 2026-09-09 08:31

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
