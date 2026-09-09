#global if #command == Swag.CompilerCommand.Test
#global private
using Core, Gui
#test
{
    Gui.registerLanguage("fr", "Fran\u00e7ais")
    for language in [Gui.ReferenceLanguage, "fr"]
    {
        for palette in 3
        {
            var host: Testing.HeadlessHost
            let window = testSetupMainWindow(&host, MainWindow.MinWidth, MainWindow.MinHeight)
            defer host.shutdown()
            window.panels[0].selectViewer(.Microcode)
            if palette == 0 do host.theme.setSwagDark()
            elif palette == 1 do host.theme.setDark()
            else do host.theme.setLight()
            host.notify(.ThemeChanged)
            discard expect applyLanguage(&host.app.resources, language)
            host.notify(.LanguageChanged)
            window.setComparisonEnabled(true)
            host.settleAnimations(window)
            var image = host.render(&host.surfaceWnd)
            let path = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("prism-review-%-%.png", language, palette))
            expect image.save(path)
            Console.println("REVIEW ", path)
        }
    }
}
