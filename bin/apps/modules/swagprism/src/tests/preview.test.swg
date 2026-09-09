#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

func awaitFrame(viewer: *PreviewViewer, after: u32 = 0)
{
    var watch: Time.Stopwatch
    watch.start()
    while viewer.running and viewer.frameCount <= after and watch.elapsedMilliseconds() < 90000
    {
        Threading.Thread.sleep(10'ms)
        viewer.poll()
    }

    if viewer.probe.failed do
        Console.print(viewer.probe.diagnostics.toString())
    Swag.assert(viewer.running and viewer.frameCount > after)
}

// The opening viewer is an executable canvas; the second panel can inspect the same source.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    Swag.assert(!window.comparisonEnabled)
    Swag.assert(window.panels[0].kind == .Render2D)
    Swag.assert(window.panels[1].kind == .Microcode)
    Swag.assert(window.panels[0].kindCombo.items.count == 3)
    Swag.assert(window.exampleCombo.items.count == 4)
    let viewer = cast(*PreviewViewer) window.panels[0].viewer!.window()
    window.compile()
    awaitFrame(viewer)
    Swag.assert(viewer.canvas.texture.isValid())
    let before     = viewer.image
    let firstFrame = viewer.frameCount
    awaitFrame(viewer, firstFrame + 2)
    Swag.assert(Memory.compare(before.pixels.buffer, viewer.image.pixels.buffer, before.byteCount) != 0)
    viewer.paused = true
    let pausedFrame = viewer.frameCount
    Threading.Thread.sleep(100'ms)
    viewer.poll()
    Swag.assert(viewer.frameCount == pausedFrame)
    var watch: Time.Stopwatch
    watch.start()
    window.shutdown()
    Swag.assert(watch.elapsedMilliseconds() < 3000)
}

// GUI controls execute in the child and receive clicks mapped from the fitted canvas.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    window.openExample(.Gui)
    let viewer = cast(*PreviewViewer) window.panels[0].viewer!.window()
    awaitFrame(viewer)
    let before = viewer.image
    let rect   = viewer.canvas.frameRect()
    host.click(viewer.canvas.localToSurface(Math.Point{rect.x + rect.width * 0.5, rect.y + rect.height * 204 / 400}))
    awaitFrame(viewer, viewer.frameCount + 2)
    Swag.assert(Memory.compare(before.pixels.buffer, viewer.image.pixels.buffer, before.byteCount) != 0)
    window.shutdown()
}

// Execution controls and the shared toolbar fit both languages and every shipped palette.
#test
{
    var sample: Image
    {
        var host: Testing.HeadlessHost
        let window = testSetupMainWindow(&host)
        defer host.shutdown()
        window.compile()
        let viewer = cast(*PreviewViewer) window.panels[0].viewer!.window()
        awaitFrame(viewer)
        sample = viewer.image
        window.shutdown()
    }

    Gui.registerLanguage("fr", "Fran\u00e7ais")
    for palette in 3
    {
        for language in [Gui.ReferenceLanguage, "fr"]
        {
            var host: Testing.HeadlessHost
            let window = testSetupMainWindow(&host, MainWindow.MinWidth, MainWindow.MinHeight)
            defer host.shutdown()
            if palette == 0 do
                host.theme.setSwagDark()
            elif palette == 1 do
                host.theme.setDark()
            else do
                host.theme.setLight()
            host.theme.metrics.surfaceWnd_ShadowSize   = 0
            host.theme.metrics.surfaceWnd_CornerRadius = 0
            host.notify(.ThemeChanged)
            discard expect applyLanguage(&host.app.resources, language)
            host.notify(.LanguageChanged)
            let viewer = cast(*PreviewViewer) window.panels[0].viewer!.window()
            viewer.canvas.update(&sample)
            viewer.output.hide()
            viewer.canvas.show()
            viewer.status.setText(Format.toString(appStrings().ui_LiveStats, 1234, 12345).toString())
            window.panels[1].selectViewer(.Gui)
            for comparison in [false, true]
            {
                window.setComparisonEnabled(comparison)
                window.applyLayout()
                Testing.assertContentFits(window)
                Swag.assert(window.liveEdit.position.right() <= window.commandBar.paddedClientRect().right())
                Swag.assert(viewer.optimCombo.position.right() <= viewer.pauseButton.position.x)
            }
        }
    }
}

// Cancelling a looping snippet retires its process without waiting for a frame or its watchdog.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    let viewer = cast(*PreviewViewer) window.panels[0].viewer!.window()
    viewer.compileSource("func shade(x, y, time: f32)->u32 { discard x; discard y; discard time; for {} }")
    var watch: Time.Stopwatch
    watch.start()
    while !Atomic.get(&viewer.probe.ready) and !viewer.task.isDone() and watch.elapsedMilliseconds() < 90000 do
        Threading.Thread.sleep(10'ms)
    Swag.assert(Atomic.get(&viewer.probe.ready) != 0)
    watch.restart()
    viewer.stop()
    Swag.assert(watch.elapsedMilliseconds() < 3000)
    Swag.assert(!viewer.running and viewer.timer == null)
}

// Changing source replaces the running child; compiler errors remain local and recoverable.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    let viewer = cast(*PreviewViewer) window.panels[0].viewer!.window()
    viewer.compileSource("func shade(x, y, time: f32)->u32 { return missingSymbol }")
    var watch: Time.Stopwatch
    watch.start()
    while viewer.running and watch.elapsedMilliseconds() < 90000
    {
        Threading.Thread.sleep(10'ms)
        viewer.poll()
    }

    Swag.assert(!viewer.running and viewer.probe.failed)
    Swag.assert(Utf8.indexOf(cast(const [..] u8) viewer.output.text().toString(), "missingSymbol") != Swag.U64.Max)
    viewer.compileSource(exampleSource(.Julia))
    awaitFrame(viewer)
    viewer.compileSource(exampleSource(.Plasma))
    Swag.assert(viewer.queued)
    while viewer.queued
    {
        Threading.Thread.sleep(10'ms)
        viewer.poll()
    }

    awaitFrame(viewer)
    Swag.assert(viewer.source.toString() == exampleSource(.Plasma))
    window.shutdown()
}

// A complete first frame makes the application surface a deterministic, real program preview.
func assertPreviewSurface(gui: bool)
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    window.openExample(gui ? .Gui : .Plasma)
    let viewer = cast(*PreviewViewer) window.panels[0].viewer!.window()
    awaitFrame(viewer)
    viewer.paused = true
    viewer.retranslate()

    // Timings vary with the machine, while the compiled first frame is deterministic.
    viewer.status.setText("640 x 400")
    host.settleAnimations(window, 6)
    var image = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, gui ? "surface.gui" : "surface.render")
    window.shutdown()
}

#[Swag.TestTag("golden")]
#test { assertPreviewSurface(false) }

#[Swag.TestTag("golden")]
#test { assertPreviewSurface(true) }

// Each viewer retains its own options when its panel is switched to another type.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    let panel  = window.panels[0]
    let render = cast(*PreviewViewer) panel.viewer!.window()
    render.optimCombo.setSelectedIndex(1, notify: false)
    panel.selectViewer(.Microcode)
    let micro = cast(*MicrocodeViewer) panel.viewer!.window()
    micro.optimCombo.setSelectedIndex(2, notify: false)
    micro.stageCombo.setSelectedIndex(3, notify: false)
    panel.selectViewer(.Gui)
    let gui = cast(*PreviewViewer) panel.viewer!.window()
    Swag.assert(gui != render and gui.optimCombo.selectedIndex == 0)
    panel.selectViewer(.Render2D)
    Swag.assert(panel.viewer!.window() == &render.wnd and render.optimCombo.selectedIndex == 1)
    panel.selectViewer(.Microcode)
    Swag.assert(panel.viewer!.window() == &micro.wnd)
    Swag.assert(micro.optimCombo.selectedIndex == 2 and micro.stageCombo.selectedIndex == 3)
}

// The idle timer compiles the last edit once and can be disabled without a pending compilation.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()
    window.editor.setFocus()
    host.sendRune(.Space, ' ')
    Swag.assert(window.editTimer != null)
    host.sendRune(.Space, ' ')
    Swag.assert(window.editTimer != null)
    host.fireTimer(window.editTimer!)
    let viewer = cast(*PreviewViewer) window.panels[0].viewer!.window()
    Swag.assert(window.editTimer == null)
    Swag.assert(viewer.source.toString() == window.editor.text().toString())
    window.editor.setFocus()
    host.sendRune(.Space, ' ')
    window.liveEdit.setState(.Unchecked)
    window.liveEdit.sigChanged.call(window.liveEdit)
    Swag.assert(window.editTimer == null)
    window.shutdown()
}
