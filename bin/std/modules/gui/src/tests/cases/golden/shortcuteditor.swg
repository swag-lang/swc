#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// In French, a system shortcut, a local shortcut and an unassigned command fit the same sheet.
#[Swag.TestTag("golden")]
#test
{
    var captured: bool
    var host:     Testing.HeadlessHost
    host.setup(1000, 750)
    host.app.setGlobalHotKeysEnabled(false)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    host.theme.setLight()
    host.notify(.ThemeChanged)
    host.root.hookOnEvent = func| |(_, event)->bool
    {
        if event is CommandStateEvent as state where state.kind == .Compute
        {
            switch state.id
            {
            case "test.open":    state.name = "Ouvrir un document"
            case "test.inspect": state.name = "Afficher l’inspecteur"
            case "test.capture": state.name = "Capturer une zone"
            default: return false
            }

            state.updatedFields.add(.Name)
            return true
        }

        return false
    }

    host.root.registerKeyShortcut(.Control, .O, "test.open")
    expect host.app.registerUserHotKey(.CtrlShift, .F9, "test.capture", &host.root)
    let lens = Lens.View.create(&host.root)
    lens.addCommands("Fichier", ["test.open", "test.inspect", "test.capture"])
    host.app.sigFrame += func|host = &host, &captured|(_)
    {
        if captured or host.app.modalSurfaces.isEmpty() do
            return
        captured = true
        let image = host.renderSurface(host.app.modalSurfaces.back())
        Pixel.Testing.assertImageGolden(&image, "shortcuts.editor.paper")
        Swag.require(host.clickModalButton(Dialog.BtnCancel))
    }

    lens.showKeyboardShortcuts()
    host.app.sigFrame.clear()
    Swag.require(captured)
}

// The nested system picker keeps both selectors and its primary action visible at 125 percent.
#[Swag.TestTag("golden")]
#test
{
    var stage: u32
    var host:  Testing.HeadlessHost
    host.setup(1000, 750, 1.25)
    host.app.setGlobalHotKeysEnabled(false)
    host.theme.setDark()
    host.notify(.ThemeChanged)
    expect host.app.registerUserHotKey(.CtrlShift, .F9, "test.system-capture", &host.root)
    let lens = Lens.View.create(&host.root)
    lens.addCommands("Capture", ["test.system-capture"])

    let capture: FrameCallback = func|host = &host, &stage|(app)
    {
        let surface = app.modalSurfaces.back()
        let root    = surface.view()
        switch stage
        {
        case 0:
            stage = 1
            host.clickWnd(unwrap root.childById("gui.shortcuts.change"))
            Swag.require(stage == 2)
            stage = 3
            Swag.require(host.clickModalButton(Dialog.BtnCancel))

        case 1:
            stage = 2

            // The CPU surface has no monitor to supply the native scale.
            let size  = surface.size()
            let scale = host.surface.dpiScale
            surface.setDpiScaleRaw(scale)
            var position = surface.position
            position.width  = Math.ceil(size.x * scale)
            position.height = Math.ceil(size.y * scale)
            surface.setPosition(position)
            root.applyLayout()
            let mods = assume cast(*ComboBox, unwrap root.childById("gui.shortcuts.modifiers"))
            let keys = assume cast(*ComboBox, unwrap root.childById("gui.shortcuts.key"))
            mods.setSelectedIndex(3)
            for item, index in keys.items where item!.name.text == "F10"
            {
                keys.setSelectedIndex(cast(u32, index))
                break
            }

            Swag.require(keys.selectedItem()!.name.text == "F10")
            let image = host.renderSurface(surface)
            Pixel.Testing.assertImageGolden(&image, "shortcuts.system-picker.encre")
            Swag.require(host.clickModalButton(Dialog.BtnCancel))
        }
    }

    host.app.sigFrame += capture
    lens.showKeyboardShortcuts()
    host.app.sigFrame.clear()
    Swag.require(stage == 3)
}
