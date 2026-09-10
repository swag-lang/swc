#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

private func awaitReplacement(viewer: *PreviewViewer)
{
    var watch: Time.Stopwatch
    watch.start()
    while viewer.queued and watch.elapsedMilliseconds() < 90000
    {
        Threading.Thread.sleep(5'ms)
        viewer.poll()
    }

    Swag.assert(not viewer.queued and viewer.running)
}

// Editing keeps the previous process alive, then publishes only the last requested complete frame.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    let viewer = cast(*PreviewViewer) window.panels[0].viewer!.window()
    viewer.compileSource("func shade(x, y, time: f32)->u32 { discard x; discard y; discard time; return 0xFF112233 }")
    awaitFrame(viewer)
    let previous = viewer.probe
    let oldFrame = viewer.frameCount
    viewer.compileSource("func shade(x, y, time: f32)->u32 { discard x; discard y; discard time; return 0xFF445566 }")
    Swag.assert(viewer.preparing != null and not Atomic.get(&previous.cancelled))
    Swag.assert(window.spinner.isVisible())
    awaitFrame(viewer, oldFrame)
    Swag.assert(viewer.probe == previous)
    viewer.compileSource("func shade(x, y, time: f32)->u32 { discard x; discard y; discard time; return 0xFF778899 }")
    viewer.compileSource("func shade(x, y, time: f32)->u32 { discard x; discard y; discard time; return 0xFFAABBCC }")
    awaitReplacement(viewer)
    Swag.assert(viewer.probe != previous and not window.spinner.isVisible())
    Swag.assert((cast([*] u32) viewer.image.pixels.buffer!)[0] == 0xFFAABBCC)
    window.shutdown()
    for entry in window.cache.entries do
        Swag.assert(entry.users == 0)
}

// A paused viewer shows one new complete frame after an edit, retaining its pause state.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    let viewer = cast(*PreviewViewer) window.panels[0].viewer!.window()
    viewer.compileSource("func shade(x, y, time: f32)->u32 { discard x; discard y; discard time; return 0xFF112233 }")
    awaitFrame(viewer)
    viewer.paused = true
    viewer.compileSource("func shade(x, y, time: f32)->u32 { discard x; discard y; discard time; return 0xFF445566 }")
    awaitReplacement(viewer)
    Swag.assert(viewer.paused and viewer.frameCount == 1)
    Swag.assert((cast([*] u32) viewer.image.pixels.buffer!)[0] == 0xFF445566)
    Threading.Thread.sleep(50'ms)
    viewer.poll()
    Swag.assert(viewer.frameCount == 1)
    viewer.compileSource("func shade(")
    awaitReplacement(viewer)
    Swag.assert(viewer.output.isVisible() and not viewer.output.text().isEmpty())
    viewer.compileSource("func shade(x, y, time: f32)->u32 { discard x; discard y; discard time; return 0xFF778899 }")
    awaitReplacement(viewer)
    Swag.assert(viewer.canvas.isVisible() and not viewer.output.isVisible())
    Swag.assert((cast([*] u32) viewer.image.pixels.buffer!)[0] == 0xFF778899)
    window.shutdown()
}
