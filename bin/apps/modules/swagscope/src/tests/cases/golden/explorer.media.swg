#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Selected provider data follows the current language and disappears on a local entry.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(880, 420)
    shipFrame(&host)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    registerAppStrings(&host.app.resources)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.onlineMovies = false
    window.onlineMusic  = false
    let explorer = Explorer.create(window.documentPanel, window)
    window.explorer       = explorer
    window.explorerActive = true
    explorer.entries.add({name: "Blade Runner.mkv", attempted: true,
                          movie: {title: "Blade Runner", imdbRating: "8.1/10", director: "Ridley Scott", actors: "Harrison Ford"}})
    explorer.entries.add({name: "notes.txt", attempted: true})
    let artwork = expect Image.load(Path.combine(testSourceRoot(#curlocation), "datas", "title.png"))
    explorer.entries[0].texture = host.app.renderer.addImage(&artwork)
    explorer.fill()
    explorer.setShown(true)
    explorer.grid.select(0)
    explorer.showInformation()
    window.applyLayout()
    Swag.require(window.infoSheet.isVisible())
    Swag.require(Utf8.contains(window.infoSheet.text(), "8.1 IMDb"))
    Swag.require(Utf8.contains(window.infoSheet.text(), "Director\nRidley Scott"))
    let english = host.render(window)
    Pixel.Testing.assertImageGolden(&english, "explorer.movie")

    discard expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    explorer.entries[0].movie = {title: "Blade Runner", imdbRating: "8.1/10", director: "Ridley Scott", actors: "Harrison Ford"}
    explorer.showMediaInfo()
    Swag.require(Utf8.contains(window.infoSheet.text(), "8.1 IMDb"))
    Swag.require(Utf8.contains(window.infoSheet.text(), "Distribution\nHarrison Ford"))
    explorer.entries[0].movie.imdbRating = "8.2/10"
    explorer.entries[0].movie.date       = "1982-06-25"
    explorer.entries[0].movie.overview   = "Un dÃ©tective dans le futur."
    explorer.showMediaInfo()
    Swag.require(Utf8.contains(window.infoSheet.text(), "8.2 IMDb"))
    Swag.require(Utf8.contains(window.infoSheet.text(), "1982"))
    Swag.require(Utf8.contains(window.infoSheet.text(), "Un dÃ©tective dans le futur."))
    explorer.entries[1].music = {title: "Discovery", artist: "Daft Punk", date: "2001-03-12"}
    explorer.grid.select(1)
    Swag.require(Utf8.contains(window.infoSheet.text(), "Discovery"))
    Swag.require(Utf8.contains(window.infoSheet.text(), "Daft Punk"))
    Swag.require(Utf8.contains(window.infoSheet.text(), "2001-03-12"))
    explorer.entries[1].music = {}
    explorer.showMediaInfo()
    Swag.require(Utf8.contains(window.infoSheet.text(), "notes.txt"))
}

// The correction prompt fits a two-sentence explanation at normal and scaled DPI.
#[Swag.TestTag("golden")]
#test
{
    for scale in [1.0'f32, 1.5'f32]
    {
        var host: Testing.HeadlessHost
        host.setup(900, 700, scale)
        shipFrame(&host)
        registerAppStrings(&host.app.resources)
        let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
        window.onlineMovies = false
        window.onlineMusic  = false
        let explorer = Explorer.create(window.documentPanel, window)
        window.explorer       = explorer
        window.explorerActive = true
        let musicDialog = explorer.createMusicChoiceDialog("48140466-cff6-3222-bd55-63c27e43190d")
        musicDialog.applyLayout()
        Swag.require(musicDialog.text() == "48140466-cff6-3222-bd55-63c27e43190d")
        Swag.require(musicDialog.label.itf.measureContent(Math.Point{musicDialog.label.position.width, 0}).y <= musicDialog.label.position.height + 0.5)
        if scale == 1.0
        {
            var image = host.renderSurface(unwrap musicDialog.surface)
            Pixel.Testing.assertImageGolden(&image, "explorer.music.choice")
        }

        musicDialog.surface!.destroy()
        host.pump()
    }
}
