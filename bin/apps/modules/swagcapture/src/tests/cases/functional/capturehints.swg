#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui

// Shortcuts follow the active monitor on staggered desktops, including negative origins and DPI.
#test
{
    for scale in [1'f32, 1.5, 2]
    {
        var host: Testing.HeadlessHost
        let main = testSetupSurfaceMain(&host, dpiScale: scale)
        defer
        {
            host.shutdown()
            g_Main = null
        }

        defer discard catch host.app.setLanguage(Gui.ReferenceLanguage)

        host.surface.setPosition({-512 * scale, -160 * scale, 1024 * scale, 640 * scale})
        main.monitors.clear()
        testAddMonitorAt(main, {-512 * scale, -160 * scale, 512 * scale, 640 * scale})
        testAddMonitorAt(main, {0, 0, 512 * scale, 480 * scale})
        g_DesktopX = cast(s32, -512 * scale)
        g_DesktopY = cast(s32, -160 * scale)

        with let overlay = Wnd.create'CaptureRectWnd(&host.surfaceWnd, {0, 0, 1024, 640})
        {
            .main = main
        }

        overlay.createHints()
        let hints = unwrap overlay.hints

        for language in Gui.languages()
        {
            expect host.app.setLanguage(language.tag)
            for monitor, index in main.monitors
            {
                var point = monitor.physicalBounds.center()
                host.surface.screenToSurface(&point)
                var move = MouseEvent{kind: .Move, surfacePos: point}
                overlay.sendEvent(&move)
                overlay.applyLayout()

                let room = index == 0 ? Math.Rectangle{0, 0, 512, 640} : Math.Rectangle{512, 160, 512, 480}
                Swag.require(hints.position == room)
                let line = hints.line.surfaceRect()
                Swag.require(line.x >= room.x and line.right() <= room.right())
                Swag.require(line.y >= room.y and line.bottom() <= room.bottom())
                Swag.require(hints.line.contentWidth() + 4 * main.themeMetrics().hintLine_KeyGap <= line.width)
                Testing.assertContentFits(hints.line)
                Swag.require(hints.line.hints.count == 3)
                for hint in hints.line.hints do
                    Swag.require(hint.key != Gui.strings().key_Tab)
            }
        }

        // Empty space above the staggered right screen still uses the nearest real monitor.
        hints.placeAt({50 * scale, -40 * scale})
        Swag.require(hints.position == {512, 160, 512, 480})

        var tab = KeyEvent{kind: .Pressed, key: .Tab}
        for media in [CaptureMedia.Picture, .Animation, .Video]
        {
            g_CaptureMedia = media
            overlay.sendEvent(&tab)
            Swag.require(g_CaptureMedia == media)
        }

        g_CaptureMedia = .Picture
    }
}
