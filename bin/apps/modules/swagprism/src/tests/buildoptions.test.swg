#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

#test
{
    Gui.registerLanguage("fr", "Fran\u00e7ais")
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
            window.setComparisonEnabled(true)
            window.panels[1].selectViewer(.Gui)
            for panel in window.panels do
                panel.showOptions(true)
            window.applyLayout()
            Testing.assertContentFits(window)
        }
    }
}
