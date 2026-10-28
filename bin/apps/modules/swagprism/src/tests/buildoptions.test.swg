#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Both build configurations, side by side at the narrowest window, keep their heading, their preset
// and their actions inside their column, in both languages and both palettes.
#test
{
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
            window.panels[1].selectViewer(.Gui)
            window.applyView(.Compare)
            for panel in window.panels do
                panel.showOptions(true)
            window.applyLayout()
            Testing.assertContentFits(window)
            for panel in window.panels
            {
                Swag.assert(panel.presetMenu.position.x >= panel.titleWidth())
                Swag.assert(panel.presetMenu.position.right() <= panel.restoreButton.position.x)
                Swag.assert(panel.restoreButton.position.right() <= panel.closeButton.position.x)
                Swag.assert(panel.closeButton.position.right() <= panel.clientRect().right())
            }
        }
    }
}
