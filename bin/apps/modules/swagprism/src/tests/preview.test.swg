#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// The opening viewer is an executable canvas; the reference build can inspect the same source.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    Swag.assert(window.view == .Columns and not window.panels[1].isVisible())
    Swag.assert(window.panels[0].kind == .Render2D)
    Swag.assert(window.panels[1].kind == .Microcode)
    Swag.assert(window.panels[0].pauseButton.isVisible() and not window.panels[0].stageMenu.isVisible())
    let viewer = assume cast(*PreviewViewer, window.panels[0].viewer!.window())
    window.compile()
    Swag.assert(window.panels[0].isRunning() and window.reading() == appStrings().ui_Working)
    awaitFrame(viewer)
    Swag.assert(not window.panels[0].isRunning())
    Swag.assert(viewer.canvas.texture.isValid())
    let before     = viewer.image
    let firstFrame = viewer.frameCount
    awaitFrame(viewer, firstFrame + 2)
    Swag.assert(Memory.compare(before.pixels.storage(), viewer.image.pixels.storage(), before.byteCount) != 0)
    host.click(window.panels[0].pauseButton.localToSurface(Math.Point{8, 8}))
    Swag.assert(viewer.paused and window.panels[0].pauseButton.name == appStrings().ui_Resume)
    let pausedFrame = viewer.frameCount
    Threading.Thread.sleep(100'ms)
    viewer.poll()
    Swag.assert(viewer.frameCount == pausedFrame)
    host.click(window.panels[0].pauseButton.localToSurface(Math.Point{8, 8}))
    Swag.assert(not viewer.paused and window.panels[0].pauseButton.name == appStrings().ui_Pause)
    awaitFrame(viewer, pausedFrame)
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
    window.openExample(.Gui)
    let viewer = assume cast(*PreviewViewer, window.panels[0].viewer!.window())
    awaitFrame(viewer)
    let before = viewer.image
    let rect   = viewer.canvas.frameRect()
    host.click(viewer.canvas.localToSurface(Math.Point{rect.x + rect.width * 0.5, rect.y + rect.height * 204 / 400}))
    awaitFrame(viewer, viewer.frameCount + 2)
    Swag.assert(Memory.compare(before.pixels.storage(), viewer.image.pixels.storage(), before.byteCount) != 0)
    window.shutdown()
}

// The headers, the frame and its switch fit both languages and both palettes at the narrowest
// window, beside the source and beside another build.
#test
{
    var sample: Image
    scope
    {
        var host: Testing.HeadlessHost
        let window = testSetupMainWindow(&host)
        window.compile()
        let viewer = assume cast(*PreviewViewer, window.panels[0].viewer!.window())
        awaitFrame(viewer)
        sample = viewer.image
        window.shutdown()
    }

    Gui.registerLanguage("fr", "Français")
    for light in [false, true]
    {
        for language in [Gui.ReferenceLanguage, "fr"]
        {
            var host: Testing.HeadlessHost
            let window = testSetupMainWindow(&host, MainWindow.MinWidth, MainWindow.MinHeight)
            if light do
                host.theme.setLight()
            host.notify(.ThemeChanged)
            discard expect applyLanguage(&host.app.resources, language)
            host.notify(.LanguageChanged)
            let viewer = assume cast(*PreviewViewer, window.panels[0].viewer!.window())
            viewer.canvas.update(&sample)
            viewer.output.scroll.hide()
            viewer.canvas.show()
            window.readingLine.setReading(Format.toString(appStrings().ui_LiveStats, 1234, 12345))
            window.panels[1].selectViewer(.Gui)
            for view in [PrismView.Columns, PrismView.Compare]
            {
                window.applyView(view)
                window.applyLayout()
                Testing.assertContentFits(window)
                if view == .Columns do
                    Swag.assert(window.exampleMenu.position.right() <= window.panels[0].position.x)
                for panel, index in window.panels where window.isShown(index)
                {
                    Swag.assert(panel.viewMenu.position.right() <= panel.optimMenu.position.x)
                    Swag.assert(panel.optimMenu.position.right() <= panel.pauseButton.position.x)
                    Swag.assert(panel.pauseButton.position.right() <= panel.clientRect().right())
                }

                Swag.assert(viewer.liveLabel.position.right() <= viewer.clientRect().right())
                Swag.assert(window.hintLine.position.right() <= window.readingLine.position.x)
            }
        }
    }
}

// Cancelling a looping snippet retires its process without waiting for a frame or its watchdog.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    let viewer = assume cast(*PreviewViewer, window.panels[0].viewer!.window())
    viewer.compileSource("func shade(_: f32, _: f32, _: f32)->u32 { for {} }")
    var watch: Time.Stopwatch
    watch.start()
    while not Atomic.get(&viewer.probe.ready) and
          not viewer.probe.task.isDone() and
          watch.elapsedMilliseconds() < 90000 do
        Threading.Thread.sleep(10'ms)
    Swag.assert(Atomic.get(&viewer.probe.ready) != 0)
    watch.restart()
    viewer.stop()
    Swag.assert(watch.elapsedMilliseconds() < 3000)
    Swag.assert(not viewer.running and viewer.timer == null)
}

// Pixel compilation excludes GUI; an unavailable dependency stays local and can be corrected.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    let viewer = assume cast(*PreviewViewer, window.panels[0].viewer!.window())
    viewer.compileSource("using Gui\nfunc shade(_: f32, _: f32, _: f32)->u32 => 0")
    var watch: Time.Stopwatch
    watch.start()
    while viewer.running and watch.elapsedMilliseconds() < 90000
    {
        Threading.Thread.sleep(10'ms)
        viewer.poll()
    }

    Swag.assert(not viewer.running and viewer.probe.failed)
    Swag.assert(viewer.output.copyText().contains("Gui"))
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
    Swag.assert(viewer.source == exampleSource(.Plasma))
    window.shutdown()
}

// A complete first frame makes the application surface a deterministic, real program preview.
func assertPreviewSurface(gui: bool, light: bool)
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    window.openExample(gui ? .Gui : .Plasma)
    let viewer = assume cast(*PreviewViewer, window.panels[0].viewer!.window())
    awaitFrame(viewer)
    host.click(window.panels[0].pauseButton.localToSurface(Math.Point{8, 8}))
    Swag.assert(viewer.paused)
    host.moveMouse({1, 1})

    // Timings vary with the machine, while the compiled first frame is deterministic.
    window.readingLine.setReading(Format.toString(appStrings().ui_LiveStats, 41, 812))
    host.settleAnimations(window, 6)
    var image = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, gui ? "surface.gui" : (light ? "surface.render.paper" : "surface.render"))
    window.shutdown()
}

#[Swag.TestTag("golden")]
#test { assertPreviewSurface(false, false) }

#[Swag.TestTag("golden")]
#test { assertPreviewSurface(false, true) }

#[Swag.TestTag("golden")]
#test { assertPreviewSurface(true, false) }

// Optimization belongs to the panel; stage and playback state belong to each cached viewer.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)

    let panel  = window.panels[0]
    let render = assume cast(*PreviewViewer, panel.viewer!.window())
    panel.setLevel(.O1, notify: false)
    host.click(panel.pauseButton.localToSurface(Math.Point{8, 8}))
    Swag.assert(render.paused and panel.pauseButton.name == appStrings().ui_Resume)

    panel.selectViewer(.Microcode)
    let micro = assume cast(*MicrocodeViewer, panel.viewer.window())
    Swag.assert(panel.request("").settings.optimization == .O1 and not panel.pauseButton.isVisible())
    panel.setLevel(.O2, notify: false)
    micro.setStage(3)
    Swag.assert(panel.stageMenu.isVisible() and panel.stageMenu.name == Pipeline.stageLabels()[3])

    panel.selectViewer(.Gui)
    let gui = assume cast(*PreviewViewer, panel.viewer.window())
    Swag.assert(gui != render and
                panel.request("").settings.optimization == .O2 and
                not gui.paused and
                panel.pauseButton.name == appStrings().ui_Pause)

    panel.selectViewer(.Render2D)
    Swag.assert(panel.viewer.window() == &render.wnd and
                panel.pauseButton.name == appStrings().ui_Resume and
                panel.pauseButton.isVisible())

    panel.selectViewer(.Microcode)
    Swag.assert(panel.viewer.window() == &micro.wnd and micro.stage == 3)
}

// The idle timer compiles the last edit once, and the switch under the frame stops it without
// leaving a compilation pending.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    window.editor.setFocus()
    host.sendRune(.Space, ' ')
    Swag.assert(window.editTimer != null)
    host.sendRune(.Space, ' ')
    Swag.assert(window.editTimer != null)
    host.fireTimer(window.editTimer)
    let viewer = assume cast(*PreviewViewer, window.panels[0].viewer!.window())
    Swag.assert(window.editTimer == null)
    Swag.assert(viewer.source == window.editor.text())
    window.editor.setFocus()
    host.sendRune(.Space, ' ')
    viewer.liveSwitch.setChecked(false)
    viewer.liveSwitch.sigChanged.call(viewer.liveSwitch)
    Swag.assert(window.editTimer == null and not window.liveEdit)
    window.shutdown()
}
