#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Accepting the correction dialogs preserves their existing IDs and retires old previews.
#test
{
    var host: Testing.HeadlessHost
    host.setup(880, 420)
    registerAppStrings(&host.app.resources)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.onlineMovies = false
    window.onlineMusic  = false
    let explorer = Explorer.create(window.documentPanel, window)
    explorer.entries.add({name: "Film.mkv", path: "C:/films/Film.mkv", size: 10, creationStamp: 1, modifiedStamp: 2})
    explorer.entries.add({name: "Music.mp3", path: "C:/music/Music.mp3", size: 20, creationStamp: 3, modifiedStamp: 4})
    let id = "48140466-cff6-3222-bd55-63c27e43190d"
    setMusicChoice(&window.musicChoices, &explorer.entries[1], id)
    explorer.hide()
    let generation = explorer.generation
    explorer.selected = 1
    host.clickModalButtonWhenShown(Dialog.BtnOk)
    explorer.chooseMusic()
    Swag.assert(host.autoHandled and musicChoiceId(window.musicChoices.toSlice(), &explorer.entries[1]) == id)
    Swag.assert(explorer.generation > generation)
}

// The options menu remains usable before any entry has been selected.
#test
{
    var host: Testing.HeadlessHost
    host.setup(880, 420)
    registerAppStrings(&host.app.resources)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.onlineMovies = false
    window.onlineMusic  = false
    let explorer = Explorer.create(window.documentPanel, window)
    explorer.show()
    window.applyLayout()
    window.onlineMusic = false
    host.clickPopupMenuItemWhenShown("onlineMusic")
    explorer.showMediaOptions()
    Swag.assert(host.autoHandled and window.onlineMusic)
}

// Selected provider data follows the current language and disappears on a local entry.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(880, 420)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    registerAppStrings(&host.app.resources)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.onlineMovies = false
    window.onlineMusic  = false
    let explorer = Explorer.create(window.documentPanel, window)
    explorer.entries.add({name: "Blade Runner.mkv", attempted: true,
                          movie: {title: "Blade Runner", imdbRating: "8.1/10", director: "Ridley Scott", actors: "Harrison Ford"}})
    explorer.entries.add({name: "notes.txt", attempted: true})
    explorer.fill()
    explorer.show()
    explorer.grid.select(0)
    window.applyLayout()
    Swag.assert(explorer.mediaInfo.isVisible())
    Swag.assert(Utf8.contains(explorer.mediaInfo.text(), "IMDb rating via Wikidata: 8.1/10"))
    Swag.assert(Utf8.contains(explorer.mediaInfo.text(), "Director: Ridley Scott"))
    let english = host.render(window)
    Pixel.Testing.assertImageGolden(&english, "explorer.movie")

    discard expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    explorer.entries[0].movie = {title: "Blade Runner", imdbRating: "8.1/10", director: "Ridley Scott", actors: "Harrison Ford"}
    explorer.showMediaInfo()
    Swag.assert(Utf8.contains(explorer.mediaInfo.text(), "Note IMDb via Wikidata : 8.1/10"))
    Swag.assert(Utf8.contains(explorer.mediaInfo.text(), "Distribution : Harrison Ford"))
    explorer.entries[0].movie.imdbRating = "8.2/10"
    explorer.entries[0].movie.date       = "1982-06-25"
    explorer.entries[0].movie.overview   = "Un détective dans le futur."
    explorer.showMediaInfo()
    Swag.assert(Utf8.contains(explorer.mediaInfo.text(), "Note IMDb via Wikidata : 8.2/10"))
    Swag.assert(Utf8.contains(explorer.mediaInfo.text(), "Sortie : 1982-06-25"))
    Swag.assert(Utf8.contains(explorer.mediaInfo.text(), "Synopsis : Un détective dans le futur."))
    explorer.entries[1].music = {title: "Discovery", artist: "Daft Punk", date: "2001-03-12"}
    explorer.grid.select(1)
    Swag.assert(Utf8.contains(explorer.mediaInfo.text(), "Discovery"))
    Swag.assert(Utf8.contains(explorer.mediaInfo.text(), "Daft Punk"))
    Swag.assert(Utf8.contains(explorer.mediaInfo.text(), "2001-03-12"))
    explorer.entries[1].music = {}
    explorer.showMediaInfo()
    Swag.assert(not explorer.mediaInfo.isLocallyVisible())
}

// The correction prompt fits a two-sentence explanation at normal and scaled DPI.
#[Swag.TestTag("golden")]
#test
{
    for scale in [1.0'f32, 1.5'f32]
    {
        var host: Testing.HeadlessHost
        host.setup(900, 700, scale)
        registerAppStrings(&host.app.resources)
        let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
        window.onlineMovies = false
    window.onlineMusic  = false
    let explorer = Explorer.create(window.documentPanel, window)
        let musicDialog = explorer.createMusicChoiceDialog("48140466-cff6-3222-bd55-63c27e43190d")
        musicDialog.applyLayout()
        Swag.assert(musicDialog.text() == "48140466-cff6-3222-bd55-63c27e43190d")
        Swag.assert(musicDialog.label.itf.measureContent(Math.Point{musicDialog.label.position.width, 0}).y <= musicDialog.label.position.height + 0.5)
        if scale == 1.0
        {
            let surface  = unwrap musicDialog.surface
            let rendered = host.render(musicDialog)
            var image    = rendered.cropped(0, 0, cast(s32, surface.position.width), cast(s32, surface.position.height))
            Pixel.Testing.assertImageGolden(&image, "explorer.music.choice")
        }

        musicDialog.surface!.destroy()
        host.pump()
    }
}

// Long provider text leaves room for the listing in each shipped palette.
#test
{
    for palette in 3
    {
        var host: Testing.HeadlessHost
        host.setup(880, 420)
        switch palette
        {
        case 0: host.theme.setSwagDark()
        case 1: host.theme.setDark()
        case 2: host.theme.setLight()
        }

        host.notify(.ThemeChanged)
        let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
        window.onlineMovies = false
    window.onlineMusic  = false
    let explorer = Explorer.create(window.documentPanel, window)
        explorer.entries.add({name: "Long movie.mkv", attempted: true,
                              movie: {title: "A long film title that fills more than a single line when the folder view is narrow",
                                      imdbRating: "8.2/10",
                                      director: "A director with a long name",
                                      actors: "First performer with a long name, Second performer with a long name, Third performer with a long name, Fourth performer with a long name"}})
        explorer.fill()
        explorer.show()
        explorer.grid.select(0)
        window.applyLayout()
        discard host.render(window)
        Swag.assert(explorer.mediaInfo.isVisible())
        Swag.assert(explorer.mediaInfo.position.height < 150)
        Swag.assert(explorer.grid.clientRect().height > 150)
    }
}
