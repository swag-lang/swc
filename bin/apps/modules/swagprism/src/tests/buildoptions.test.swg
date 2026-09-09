#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

#test
{
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
            window.setComparisonEnabled(true)
            window.panels[1].selectViewer(.Gui)
            for panel in window.panels do
                panel.showOptions(true)
            window.applyLayout()
            Testing.assertContentFits(window)
        }
    }
}
