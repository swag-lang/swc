#global public

using Core

// Per-frame cost recorder, armed from the command line of the running program.
//
// A window's fluidity is a property of the machine it draws on, so the numbers that decide whether
// a change helped have to come from the real application on a real adapter. A headless render
// answers a different question: it proves what the painter recorded, never what the adapter took
// to execute it.
//
// Arm it with `swag.frametrace=<file>`, which writes the summary there when the run loop ends, or
// with no value to print it. `swag.framestress=<frames>` adds a repeatable load rather than
// whatever the user happened to do: it maximizes every surface, repaints it completely on every
// frame, and stops the loop once that many frames have been measured. `swag.framestressbox=<side>`
// narrows that repaint to one square travelling across the window, which is the shape of a dragged
// widget and the case a window that repaints and presents whole hides.
struct FrameTrace
{
    enabled:   bool       // Whether the run records frames at all.
    stressing: bool       // Whether every frame invalidates its surfaces completely.
    boxSide:   f32        // Side of the moving box a partial stress invalidates, or zero for the whole surface.
    path:      String     // File the summary is written to, empty for standard output.
    maxFrames: u64        // Measured frames the stress run stops after, or zero when unbounded.

    // Accumulated cost of the run, in microseconds.
    totalUs:   u64        // Whole frames, from the start of one to the start of the next.
    recordUs:  u64        // Recording the hierarchy and the chrome into the painter.
    targetUs:  u64        // Submitting the recorded frame to the adapter as the render-target pass.
    presentUs: u64        // Copying that target to the back buffer and presenting it.
    frames:    u64        // Frames the totals cover.
    warmedUp:  u64        // Frames already dropped as warm-up.
    worstUs:   u64        // The worst frame of the run, which is what a stall actually feels like.
    pixels:    u64        // Device pixels the dirty rectangles covered, to tell a cheaper frame from a smaller one.
    vertices:  u64        // Vertices the recording emitted, which is what bounds the recording cost.
    batches:   u64        // Draw commands the recording emitted, which is what bounds the state changes.

    // What the batch bound saved, counted rather than timed: the pixels the overlap-safe path
    // actually cleared, and the pixels it would have cleared unbounded, on the same frames.
    scratchPixels: u64     // Alpha scratch the overlap-safe path cleared.
    scratchFull:   u64     // Alpha scratch it would have cleared with no per-batch bound.

    watch:     Time.Stopwatch
}

// Frames dropped before the totals start, letting the adapter, the caches and the atlases settle.
private const WarmUpFrames = 20'u64

// Measured frames a stress run defaults to when its marker carries no usable count.
private const DefaultStressFrames = 300'u64

// Side of the moving box a partial stress uses when its marker carries no usable size.
private const DefaultStressBoxSide = 300.0'f32

internal impl FrameTrace
{
    // Reads the command line and arms the recorder.
    mtd setup()
    {
        let trace = findMarker("swag.frametrace")
        if !trace.found do
            return

        .enabled = true
        .path    = trace.value

        let stress = findMarker("swag.framestress")
        if stress.found
        {
            .stressing = true
            let frames = catch StrConv.toU64(stress.value)
            .maxFrames = frames != 0 ? frames : DefaultStressFrames
        }

        // A partial stress moves one box around instead of repainting everything, which is the
        // shape of every dragged widget: a small region changes and the rest of the window does
        // not. It is the case a surface that repaints and presents by the whole window hides.
        let box = findMarker("swag.framestressbox")
        if box.found
        {
            let side = catch StrConv.toF32(box.value)
            .boxSide = side > 0 ? side : DefaultStressBoxSide
        }
    }

    // Returns where the moving box sits this frame, inside a surface of `size`.
    //
    // It travels on a diagonal so it crosses the window rather than staying over one widget, and
    // wraps rather than bouncing so every frame of a run costs the same.
    mtd const movingBox(size: Math.Point)->Math.Rectangle
    {
        let side  = Math.min(.boxSide, Math.min(size.x, size.y))
        let spanX = Math.max(size.x - side, 1.0'f32)
        let spanY = Math.max(size.y - side, 1.0'f32)
        let step  = cast(f32) (.frames + .warmedUp)
        let x = step * 7 - Math.floor(step * 7 / spanX) * spanX
        let y = step * 5 - Math.floor(step * 5 / spanY) * spanY
        return {x, y, side, side}
    }

    // Reports whether the run has measured everything it was asked for.
    mtd const isComplete() => .maxFrames != 0 and .frames >= .maxFrames

    // Starts timing one frame.
    mtd beginFrame()
    {
        if .enabled do
            .watch.restart()
    }

    // Adds one surface's recorded and executed cost, and the area it covered.
    mtd addSurface(recordUs, targetUs, presentUs, pixels, vertices, batches: u64)
    {
        if !.enabled do
            return
        .recordUs  += recordUs
        .targetUs  += targetUs
        .presentUs += presentUs
        .pixels    += pixels
        .vertices  += vertices
        .batches   += batches
    }

    // Adds what the batch bound saved on one surface's frame.
    mtd addSavings(scratch, scratchFull: u64)
    {
        if !.enabled do
            return
        .scratchPixels += scratch
        .scratchFull   += scratchFull
    }

    // Closes one frame, dropping it while the run is still warming up.
    mtd endFrame()
    {
        if !.enabled do
            return

        let us = .watch.elapsedMicroseconds()
        if .warmedUp < WarmUpFrames
        {
            .warmedUp += 1
            .recordUs  = 0
            .targetUs  = 0
            .presentUs = 0
            .pixels    = 0
            .vertices  = 0
            .batches   = 0
            .scratchPixels, .scratchFull = 0
            return
        }

        .frames  += 1
        .totalUs += us
        .worstUs = Math.max(.worstUs, us)
    }

    // Writes what the run measured, once, when the loop is over.
    mtd report()
    {
        if !.enabled or !.frames do
            return

        let frames = cast(f64) .frames
        let avgMs  = cast(f64) .totalUs / frames / 1000.0

        var text: StrConv.StringBuilder
        text.appendFormat("frames      %\n", .frames)
        text.appendFormat("average     % ms\n", round2(avgMs))
        text.appendFormat("fps         %\n", round2(1000.0 / avgMs))
        text.appendFormat("worst       % ms\n", round2(cast(f64) .worstUs / 1000.0))
        text.appendFormat("record      % ms\n", round2(cast(f64) .recordUs / frames / 1000.0))
        text.appendFormat("target      % ms\n", round2(cast(f64) .targetUs / frames / 1000.0))
        text.appendFormat("present     % ms\n", round2(cast(f64) .presentUs / frames / 1000.0))
        text.appendFormat("megapixels  %\n", round2(cast(f64) .pixels / frames / 1000000.0))
        text.appendFormat("kvertices   %\n", round2(cast(f64) .vertices / frames / 1000.0))
        text.appendFormat("scratch Mpx % of %\n", round2(cast(f64) .scratchPixels / frames / 1000000.0), round2(cast(f64) .scratchFull / frames / 1000000.0))
        text.appendFormat("batches     %\n", round2(cast(f64) .batches / frames))

        let content = text.toString()
        if .path.isEmpty()
        {
            Console.println(content)
            return
        }

        catch File.writeAllBytes(.path.toString(), content.toSlice())
    }
}

// One command-line marker and the value that followed its '='.
private struct Marker
{
    found: bool
    value: string = ""
}

// Returns whether the command line carries the marker `name`, and what followed its '='.
//
// The recorder is armed after the runtime has published the argument vector, so unlike the sandbox
// it has no reason to read the operating-system command line for itself.
private func findMarker(name: string)->Marker
{
    var result: Marker

    for arg in Env.arguments()
    {
        if arg.count < name.count do
            continue
        if arg[0 until name.count] != name do
            continue

        if arg.count == name.count
        {
            result.found = true
            return result
        }

        if arg[name.count] == '='
        {
            result.found = true
            result.value = arg[name.count + 1 until arg.count]
            return result
        }
    }

    return result
}

// Rounds to two decimals, which is the precision a frame time is read at.
private func round2(value: f64)->f64 => Math.round(value * 100) / 100
