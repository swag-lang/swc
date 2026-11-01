#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Details show known media durations alongside the file information in both themes and languages.
#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
        for language in [ReferenceLanguage, "fr"]
        {
            var host: Testing.HeadlessHost
            host.setup(ViewerWindow.MinWidth, 680)
            shipFrame(&host)
            registerAppStrings(&host.app.resources)
            if light do
                host.theme.setLight()
            else do
                host.theme.setDark()
            host.notify(.ThemeChanged)
            let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
            window.onlineMovies = false
            window.onlineMusic  = false
            let explorer = Explorer.create(window.documentPanel, window)
            window.explorer       = explorer
            window.explorerActive = true
            expect host.app.setLanguage(language)
            host.notify(.LanguageChanged)
            explorer.address.breadcrumb.clear()
            explorer.address.breadcrumb.addItem("Videos")
            explorer.address.refreshPath()
            explorer.title.setText("Films")
            explorer.entries.add({name: "A Film.mkv", path: "A Film.mkv", size: 2_400_000_000,
                                  duration: 7020, modified: "2026-10-12 14:26", attempted: true})
            explorer.entries.add({name: "A Song.flac", path: "A Song.flac", size: 42_000_000,
                                  duration: 237, modified: "2026-10-10 09:08", attempted: true})
            explorer.entries.add({name: "notes.txt", path: "notes.txt", size: 12_000,
                                  modified: "2026-10-08 17:42", attempted: true})
            explorer.setMode(.Details)
            explorer.fill()
            explorer.selected = 0
            explorer.list.setFocusedIndex(0, ensureVisible: false)
            explorer.list.selectLine(0)
            explorer.show()
            window.applyLayout()

            Swag.assert(explorer.list.header.items.count == 5)
            Swag.assert(explorer.list.header.itemAt(4).name.raw == appStrings().explore_Duration)
            let fillLine = unwrap explorer.list.onFillVirtualLine
            var first:  ListLine
            var second: ListLine
            fillLine(explorer.list, &first, 0)
            fillLine(explorer.list, &second, 1)
            Swag.assert(first.itemAt(4).name.raw == "1:57:00")
            Swag.assert(second.itemAt(4).name.raw == "3:57")
            let image = host.render(window)
            let name  = light ? (language == "fr" ? "explorer.details.paper.fr" : "explorer.details.paper") :
                        (language == "fr" ? "explorer.details.encre.fr" : "explorer.details.encre")
            Pixel.Testing.assertImageGolden(&image, name)
        }
    }
}
