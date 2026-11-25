#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui, Pixel

// Startup and the pointer menu share their command list and settings.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    defer discard catch host.app.setLanguage(Gui.ReferenceLanguage)

    testAddMonitorAt(main, {1440, 0, 1440, 900})
    for language in Gui.languages()
    {
        expect host.app.setLanguage(language.tag)
        main.hubBounds = {}
        let centered = testOpenResidentPanel(&host, main, .Centered)
        let pointer  = testOpenResidentPanel(&host, main, .AtPointer)
        for id in [ActionCapture.Area, ActionCapture.FullScreen, ActionCapture.ActiveWnd, ActionCapture.RecordVideo] do
            Swag.require(testPanelOffers(centered, id) and testPanelOffers(pointer, id))
        Swag.require(centered.surface!.flags.has(.SmallCaption))
        Swag.require(not pointer.surface!.flags.has(.SmallCaption))
        Swag.require(testPanelOffers(centered, ActionGlobal.Minimize))
        Swag.require(centered.menu.items.last()!.id == ActionGlobal.Exit)
        Swag.require(pointer.menu.items.last()!.id == ActionGlobal.Exit)
        Swag.require(not testPanelOffers(pointer, ActionGlobal.Minimize))
        Swag.require(testPanelOffers(pointer, ActionGlobal.ShowHub) and testPanelOffers(pointer, ActionGlobal.Exit))

        Testing.assertContentFits(centered)
        Testing.assertContentFits(pointer)

        let work = Env.monitorForPoint({}).physicalWorkArea
        let centeredBounds = centered.surface.position
        Swag.require(Math.abs(centeredBounds.horzCenter() - work.horzCenter()) <= 1)
        Swag.require(Math.abs(centeredBounds.vertCenter() - work.vertCenter()) <= 1)

        let anchor = Math.Point{work.right() - 8, work.bottom() - 8}
        pointer.place(anchor)
        let pointerBounds = pointer.surface.position
        Swag.require(pointer.anchor == anchor)
        Swag.require(pointerBounds.x >= work.x and pointerBounds.right() <= work.right())
        Swag.require(pointerBounds.y >= work.y and pointerBounds.bottom() <= work.bottom())
        Swag.require(pointerBounds.right() >= anchor.x and pointerBounds.bottom() >= anchor.y)
        centered.close()
        pointer.close()
    }
}

// The hub opens immediately, and loading a recent picture changes only the editor.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    Swag.require(not main.recentWnd.loadDone)
    main.sendCommandEvent(ActionGlobal.ShowHub)
    let panel   = unwrap main.residentPanel
    let surface = unwrap panel.surface
    let bounds  = surface.position
    let count   = panel.menu.items.count

    main.recentWnd.addRecent("recent.scc", testFramePicture(80, 8))
    host.pump()
    Swag.require(main.recentWnd.recentView.items.count == 1)
    Swag.require(main.residentPanel == panel and surface.position == bounds)
    Swag.require(panel.menu.items.count == count)
    panel.close()
}

// Common commands fit the hub. Other targets are one step away in either placement.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    var panel = testOpenResidentPanel(&host, main, .AtPointer)
    Swag.require(main.residentPanel == panel)
    for id in [ActionGlobal.ShowLibrary, ActionGlobal.ShowEditor, ActionCapture.Area, ActionCapture.FullScreen,
               ActionCapture.ActiveWnd, ActionCapture.RecordVideo, ResidentPanel.MoreCaptures,
               ActionGlobal.ShowHub, ActionGlobal.Exit] do
        Swag.require(testPanelOffers(panel, id), id)
    for item, index in panel.menu.items where item and item.id == ActionCapture.RecordVideo
    {
        Swag.require(item.rightName.text == Input.formatKeyShortcut(.CtrlShift, .F10))
        Swag.require(panel.menu.items[index - 1]!.separator and panel.menu.items[index + 1]!.separator)
        Swag.require(panel.menu.items[index - 2]!.id == ResidentPanel.MoreCaptures)
    }

    for item, index in panel.menu.items where item and item.name.text == appStrings().ui_MenuCaptureSetup
    {
        Swag.require(not panel.menu.items[index - 1]!.separator)
        Swag.require(panel.menu.items[index - 2]!.name.text == appStrings().ui_AfterPictureCapture)
    }

    Swag.require(not testPanelOffers(panel, ActionGlobal.Minimize))
    Swag.require(not testPanelOffers(panel, ActionOptions.Options))
    Swag.require(not testPanelOffers(panel, ActionCapture.LastArea))
    Swag.require(not testPanelOffers(panel, ActionCapture.RecordScreen))

    // The waits stand in the menu as one row of choices.
    Swag.require(panel.menu.children.count == 2)
    let delays = assume cast(*StackLayoutCtrl, panel.menu.children[1])
    Swag.require(delays.children.count == CaptureDelays.count + 1)
    panel.choose(ResidentPanel.MoreCaptures)
    for id in [ActionCapture.LastArea, ActionCapture.RecordScreen, ActionCapture.RecordActiveWindow, ActionCapture.Record] do
        Swag.require(testPanelOffers(panel, id), id)
    Swag.require(not testPanelOffers(panel, ActionCapture.screenId(0)))
    Swag.require(not testPanelOffers(panel, ActionCapture.recordScreenId(0)))
    panel.choose(ResidentPanel.BackToCaptures)
    Swag.require(testPanelOffers(panel, ActionCapture.Area))

    // With a second monitor, each one can be captured and recorded. Opening a panel takes the
    // previous one off the screen.
    testAddMonitorAt(main, {1440, 0, 1440, 900})
    let previous = panel
    panel = testOpenResidentPanel(&host, main, .AtPointer)
    Swag.require(main.residentPanel == panel and panel != previous)
    Swag.require(not testPanelOffers(panel, ActionCapture.screenId(1)))
    Swag.require(not testPanelOffers(panel, ActionCapture.recordScreenId(1)))
    panel.choose(ResidentPanel.MoreCaptures)
    Swag.require(testPanelOffers(panel, ActionCapture.screenId(1)))
    Swag.require(testPanelOffers(panel, ActionCapture.recordScreenId(1)))
    panel.close()
    Swag.require(main.residentPanel == null)
}

// The preview keeps the latest successful copy at thumbnail size.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    expect Clipboard.resetFake()
    defer Clipboard.clear()
    let first = Testing.indexedImage(240, 80)
    Swag.require(main.copyScreenshot(first))
    Swag.require(main.clipboardPreview.width == ResidentPanel.ClipboardPreviewWidth)
    Swag.require(main.clipboardPreview.height == 40)
    Swag.require(Clipboard.getImage().width == first.width)

    let second = Testing.indexedImage(24, 84)
    Swag.require(main.copyScreenshot(second))
    Swag.require(main.clipboardPreview.width == 16)
    Swag.require(main.clipboardPreview.height == ResidentPanel.ClipboardPreviewHeight)
    Swag.require(Clipboard.getImage().height == second.height)

    Swag.require(not main.copyScreenshot(Image{}))
    Swag.require(main.clipboardPreview.width == 16 and main.clipboardPreview.height == ResidentPanel.ClipboardPreviewHeight)
    Swag.require(Clipboard.getImage().height == second.height)
}

// The hub keeps capture delay choices available without dismissing the next capture command.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    defer discard catch host.app.setLanguage(Gui.ReferenceLanguage)
    for language in Gui.languages()
    {
        expect host.app.setLanguage(language.tag)
        main.captureOptions.delay = 7
        let panel   = testOpenResidentPanel(&host, main, .Centered)
        let surface = unwrap panel.surface
        surface.show()
        let choices = assume cast(*StackLayoutCtrl, panel.menu.children[1])
        Swag.require(choices.children.count == CaptureDelays.count + 1)
        Swag.require(testPanelOffers(panel, ActionCapture.Area))
        Testing.assertContentFits(panel)

        let cursor         = assume cast(*IconButton, choices.children[0])
        let previousCursor = main.captureOptions.captureCursor
        Swag.require(cursor.flags.has(.Toggle) and cursor.name.text == appStrings().ui_AimCursor)
        host.clickWnd(cursor)
        host.pump()
        Swag.require(main.captureOptions.captureCursor != previousCursor and cursor.isChecked != previousCursor)
        Swag.require(cursor.name.text == appStrings().ui_AimCursor)
        Swag.require(main.residentPanel == panel and not panel.menu.isModalEnded())

        for choice, index in CaptureDelays
        {
            let button = assume cast(*IconButton, choices.children[index + 1])
            let bounds = button.surfaceRect()
            Swag.require(bounds.x >= 0 and bounds.right() <= surface.position.width / surface.dpiScale)
            Swag.require(button.position.height == cursor.position.height)
            Swag.require(Math.abs(button.position.vertCenter() - cursor.position.vertCenter()) <= 0.5)
            host.clickWnd(button)
            host.pump()
            Swag.require(main.captureOptions.delay == choice.seconds)
            Swag.require(main.residentPanel == panel and not panel.menu.isModalEnded())
            Swag.require(cursor.isChecked != previousCursor)
            for child, other in choices.children where other > 0 do
                Swag.require((assume cast(*IconButton, child)).isChecked == (other == index + 1))
        }

        panel.close()
    }
}

// The picture destination can be chosen by click or keyboard, without leaving the hub.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    testAddMonitorAt(main, {1440, 0, 1440, 900})
    let panel   = testOpenResidentPanel(&host, main, .Centered)
    let choices = unwrap panel.pictureChoices
    let surface = unwrap panel.surface
    surface.show()
    let clipboard = assume cast(*IconButton, choices.children[0])
    let annotate  = assume cast(*IconButton, choices.children[1])
    let editor    = assume cast(*IconButton, choices.children[2])
    Swag.require(annotate.isChecked and not clipboard.isChecked and not editor.isChecked)
    host.clickWnd(clipboard)
    host.pump()
    Swag.require(clipboard.isChecked and not annotate.isChecked and not editor.isChecked)
    Swag.require(main.captureOptions.pictureDestination == .Clipboard)
    Swag.require(main.residentPanel == panel and not panel.menu.isModalEnded())

    var down      = KeyEvent{kind: .Pressed, key: .Down}
    var selecting = true
    var destinationHeading: bool
    for item in panel.menu.items
    {
        let entry = unwrap item
        if selecting and not entry.disabled and not entry.separator and not entry.label
        {
            panel.sendEvent(&down)
            selecting = not destinationHeading
        }

        if entry.label and entry.name.text == appStrings().ui_AfterPictureCapture do
            destinationHeading = true
    }

    var left = KeyEvent{kind: .Pressed, key: .Left}
    panel.sendEvent(&left)
    Swag.require(left.accepted and editor.isChecked and not clipboard.isChecked and not annotate.isChecked)
    Swag.require(main.captureOptions.pictureDestination == .Editor)

    for secondary in [false, true]
    {
        if secondary do
            panel.choose(ResidentPanel.MoreCaptures)
        var icons: Array'Icon
        for item in panel.menu.items where item!.icon.isValid()
        {
            for existing in icons do
                Swag.require(existing.imageList != item.icon.imageList or existing.index != item.icon.index, item.name.text)
            icons.add(item.icon)
        }
    }

    var escape = KeyEvent{kind: .Pressed, key: .Escape}
    panel.sendEvent(&escape)
    Swag.require(escape.accepted and testPanelOffers(panel, ActionCapture.Area))
    Swag.require(main.captureOptions.pictureDestination == .Editor and main.residentPanel == panel)
    panel.close()
}

// Both placements can open the extra targets and return to the hub by keyboard.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    for placement in [ResidentPanelPlacement.Centered, ResidentPanelPlacement.AtPointer]
    {
        let panel = testOpenResidentPanel(&host, main, placement)
        var down  = KeyEvent{kind: .Pressed, key: .Down}
        for item in panel.menu.items where item and not item.disabled and not item.label and not item.separator
        {
            panel.sendEvent(&down)
            if item.id == ResidentPanel.MoreCaptures do
                break
        }

        var enter = KeyEvent{kind: .Pressed, key: .Return}
        panel.sendEvent(&enter)
        Swag.require(enter.accepted and testPanelOffers(panel, ActionCapture.LastArea))

        var escape = KeyEvent{kind: .Pressed, key: .Escape}
        panel.sendEvent(&escape)
        Swag.require(escape.accepted and testPanelOffers(panel, ActionCapture.Area))
        panel.sendEvent(&escape)
        Swag.require(escape.accepted)
        if placement == .Centered
        {
            Swag.require(main.residentPanel == panel)
            panel.close()
        }
        else
        {
            Swag.require(main.residentPanel == null)
        }
    }
}

// While a recording runs the panel offers to stop or abandon it, not to start another capture.
#test
{
    var host: Testing.HeadlessHost
    let main     = testSetupSurfaceMain(&host)
    let recorder = Memory.new'Recorder()
    defer
    {
        g_Recorder = null
        Memory.delete(recorder)
        host.shutdown()
        g_Main = null
    }

    recorder.main = main
    g_Recorder    = recorder
    for placement in [ResidentPanelPlacement.Centered, ResidentPanelPlacement.AtPointer]
    {
        let panel = testOpenResidentPanel(&host, main, placement)
        Swag.require(testPanelOffers(panel, ActionCapture.RecordVideo))
        Swag.require(testPanelOffers(panel, ActionCapture.CancelRecording))
        Swag.require(testPanelOffers(panel, ActionGlobal.ShowEditor))
        Swag.require(not testPanelOffers(panel, ActionCapture.Area))
        Swag.require(not testPanelOffers(panel, ActionCapture.Record))
        panel.close()
    }
}

// A choice takes the panel off the screen, then runs on the main window: the editor comes back
// from behind the icon.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    let surface = unwrap main.surface
    surface.hide()
    Swag.require(surface.isHidden)

    var panel = testOpenResidentPanel(&host, main, .Centered)
    panel.choose(ActionGlobal.ShowEditor)
    host.pump()
    Swag.require(main.residentPanel == null)
    Swag.require(not surface.isHidden)

    // Leaving without a choice changes nothing.
    surface.hide()
    panel = testOpenResidentPanel(&host, main, .AtPointer)
    panel.choose(null)
    host.pump()
    Swag.require(main.residentPanel == null and surface.isHidden)
}

// The Library command from the capture window shows the library on its first frame.
#test
{
    var host: Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let surface = unwrap main.surface
    host.setReducedMotion(false)

    var shows: u64
    main.hookOnEvent = func|main, count = &shows|(_, evt)->bool
    {
        if evt is StateEvent as state where state.kind == .Show
        {
            Swag.require(main.libraryMode and main.libWnd.isLocallyVisible())
            Swag.require(not main.editArea.isLocallyVisible())
            Swag.require(main.libWnd.presentationOffset == Math.Point{})
            count[] += 1
        }

        return false
    }

    defer main.hookOnEvent = null

    for i in 2
    {
        main.showHub()
        Swag.require(main.workspace == .Hub and surface.isHidden)
        main.residentPanel!.choose(ActionGlobal.ShowLibrary)
        host.pump()
        Swag.require(shows == i + 1 and not surface.isHidden and main.residentPanel == null)
    }
}
