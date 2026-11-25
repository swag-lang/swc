#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// Locate the options editor in the actual dialog created by the application command.
func findOptionsEditor(wnd: *Wnd)->*PropertiesCtrl?
{
    if wnd is PropertiesCtrl as editor do
        return editor
    for child in wnd.children
    {
        if let found = findOptionsEditor(child) do
            return found
    }

    return null
}

func assertOptionsGolden(kind: PropertiesKind, name: string, dark: bool, tab: u32, scrollToEnd = false)
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: dark, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    main.captureOptions = CaptureOptions{hideEditorBefore: false}

    var captured: bool
    host.app.sigFrame += func|host = &host, captured = &captured, kind, name, tab, scrollToEnd|(_)
    {
        if captured[] do
            return

        for surface in host.app.surfaces where surface.view() is Gui.Dialog
        {
            captured[] = true
            let editor = unwrap findOptionsEditor(surface.view())
            editor.setKind(kind)
            editor.tab.setSelectedIndex(tab)
            surface.wnd.applyLayout()
            if scrollToEnd
            {
                let scroll = editor.properties.scrollWnd
                scroll.setScrollPos(0, scroll.scrollSize.y)
            }

            let image = host.renderSurface(surface)
            Pixel.Testing.assertImageGolden(&image, name)
            let dismissed = host.clickModalButton(Gui.Dialog.BtnCancel)
            Swag.require(dismissed)
            break
        }
    }

    main.sendCommandEvent(ActionOptions.Options)
    host.pump()
    Swag.require(captured)
}

// List shows checked, unchecked and changed settings together with their help.
#[Swag.TestTag("golden")]
#test { assertOptionsGolden(.List, "options.capture.encre", dark: true, tab: 0) }

// Grid keeps a long setting name in the same column as its shorter neighbors.
#[Swag.TestTag("golden")]
#test { assertOptionsGolden(.Grid, "options.grid.editor.paper", dark: false, tab: 2) }

// Condensed shows the capture settings together, from their switches to the recording limits.
#[Swag.TestTag("golden")]
#test { assertOptionsGolden(.Condensed, "options.condensed.capture.encre", dark: true, tab: 1) }

// Panel leaves room for the recording captions, their segmented choices and the slider tracks.
#[Swag.TestTag("golden")]
#test { assertOptionsGolden(.Panel, "options.panel.recording.paper", dark: false, tab: 1, scrollToEnd: true) }
