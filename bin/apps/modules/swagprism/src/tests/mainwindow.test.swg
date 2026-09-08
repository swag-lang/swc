#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui

// Builds the real main window inside the same measured frame as the shipped surface.
func testSetupMainWindow(host: *Testing.HeadlessHost, width = cast(f32) MainWindow.WindowWidth, height = cast(f32) MainWindow.WindowHeight, scale = 1.0'f32)->*MainWindow
{
    host.setup(width, height, scale)
    host.bindApplication(&g_App)

    // The window resolves its application through its surface, so that is the one a language
    // switch travels through and the one that has to be able to find the translations. The module
    // global gets them too, because the code under test reads `g_App` directly.
    registerAppStrings(&g_App.resources)
    registerAppStrings(&host.app.resources)

    let result = MainWindow.create(&host.surfaceWnd)
    host.surface.setTitle(ProductName)
    result.applyLayout()
    return result
}

// The stage list offers the whole table and opens on the stage the reader wants first.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    Swag.assert(window.stageCombo.items.count == Pipeline.Stages.count)
    Swag.assert(window.stageCombo.selectedIndex == Pipeline.DefaultStage)
}

// The window opens on its idle status rather than on the outcome of a compilation it never ran.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    Swag.assert(window.status.name == appStrings().ui_Ready)
}

// The editor opens on the starter snippet, and that snippet is one the probe can inspect.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    let text      = window.editor.text()
    let inspected = Pipeline.inspectedSource(text.toString(), "pre-emit", true)
    Swag.assert(Utf8.indexOf(cast(const [..] u8) inspected.toString(), "#[Swag.PrintMicro") != Swag.U64.Max)
}

// The whole surface, in the palette the application ships on.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    defer host.shutdown()

    host.theme.setSwagDark()

    // The chrome is not part of what this image pins: a headless surface has no desktop under it,
    // so its shadow falls on nothing and its rounded corner only punches holes in the captured
    // pixels. `HeadlessHost.setup` squares it for that reason, and applying a palette puts the
    // geometry of that palette back, so it is squared again here.
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    window.applyLayout()
    host.settleAnimations(window, 6)

    var image = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&image, "surface")
}

/*
The layout survives every language the application ships, at its narrowest declared width.

The window is what is measured, not the surface: the appearance action lives in the caption, which
a headless host builds but never arranges, so a check that walked the surface would report the
caption rather than the layout this test is about.
*/
#test
{
    for language in Gui.languages()
    {
        var host: Testing.HeadlessHost
        let window = testSetupMainWindow(&host, MainWindow.MinWidth, MainWindow.MinHeight)
        defer host.shutdown()

        discard catch applyLanguage(&host.app.resources, language.tag)
        host.notify(.LanguageChanged)
        window.applyLayout()
        Testing.assertContentFits(window)
    }
}
