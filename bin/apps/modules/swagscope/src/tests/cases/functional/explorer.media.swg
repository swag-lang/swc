#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Audio

// Accepting the correction dialogs preserves their existing IDs and retires old previews.
#test
{
    var host: Testing.HeadlessHost
    host.setup(880, 420)
    registerAppStrings(&host.app.resources)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.onlineMovies = false
    window.onlineMusic  = false
    let explorer = Explorer.create(window.documentPanel, window)
    window.explorer       = explorer
    window.explorerActive = true
    explorer.entries.add({name: "Film.mkv", path: "C:/films/Film.mkv", size: 10, creationStamp: 1, modifiedStamp: 2})
    explorer.entries.add({name: "Music.mp3", path: "C:/music/Music.mp3", size: 20, creationStamp: 3, modifiedStamp: 4})
    let id = "48140466-cff6-3222-bd55-63c27e43190d"
    setMusicChoice(&window.musicChoices, &explorer.entries[1], id)
    explorer.hide()
    let generation = explorer.generation
    explorer.selected = 1
    host.clickModalButtonWhenShown(Dialog.BtnOk)
    explorer.chooseMusic()
    Swag.require(host.autoHandled and musicChoiceId(window.musicChoices.toSlice(), &explorer.entries[1]) == id)
    Swag.require(explorer.generation > generation)
}

// The online media commands stay in the lens before any entry has been selected.
#test
{
    var host: Testing.HeadlessHost
    host.setup(880, 420)
    registerAppStrings(&host.app.resources)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.onlineMovies = false
    window.onlineMusic  = false
    let explorer = Explorer.create(window.documentPanel, window)
    window.explorer       = explorer
    window.explorerActive = true
    explorer.show()
    window.applyLayout()
    let music = window.sendComputeCommandStateEvent(ViewerCommands.OnlineMusic)
    Swag.require(not music.hidden and music.updatedFields.has(.Checked) and not music.checked)
    Swag.require(window.sendComputeCommandStateEvent(ViewerCommands.ChooseMusic).disabled)
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
        case 0: host.theme.setDark()
        case 1: host.theme.setDark()
        case 2: host.theme.setLight()
        }

        host.notify(.ThemeChanged)
        let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
        window.onlineMovies = false
        window.onlineMusic  = false
        let explorer = Explorer.create(window.documentPanel, window)
        window.explorer       = explorer
        window.explorerActive = true
        explorer.entries.add({name: "Long movie.mkv", attempted: true,
                              movie: {title: "A long film title that fills more than a single line when the folder view is narrow",
                                      imdbRating: "8.2/10",
                                      director: "A director with a long name",
                                      actors: "First performer with a long name, Second performer with a long name, Third performer with a long name, Fourth performer with a long name"}})
        explorer.fill()
        explorer.show()
        explorer.grid.select(0)
        explorer.showInformation()
        window.applyLayout()
        discard host.render(window)
        Swag.require(window.infoSheet.isVisible())
        Swag.require(window.infoSheet.position.bottom() <= window.clientRect().bottom())
        Swag.require(explorer.grid.clientRect().height > 150)
    }
}

// A film without online details is titled and dated by its release name, keeps that name in its
// file readings, and says how to turn the lookups on.
#test
{
    var host: Testing.HeadlessHost
    host.setup(880, 420)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.onlineMovies = false
    let explorer = Explorer.create(window.documentPanel, window)
    window.explorer       = explorer
    window.explorerActive = true
    explorer.entries.add({name: "Blade.Runner.1982.Final.Cut.1080p.mkv", size: 123, attempted: true})
    explorer.fill()
    explorer.show()
    explorer.showInformation()
    window.applyLayout()
    explorer.grid.select(0)
    let text = window.infoSheet.text()
    Swag.require(Utf8.startsWith(text, "Blade Runner\n1982 · MKV"))
    Swag.require(Utf8.contains(text, "Name\nBlade.Runner.1982.Final.Cut.1080p.mkv"))
    let foot = Format.toString("% %", appStrings().explore_OnlineOff, appStrings().explore_TurnOn)
    Swag.require(Utf8.contains(text, foot.toString()))
}

// Available facts make separate readings; selecting another file describes it instead.
#test
{
    var host: Testing.HeadlessHost
    host.setup(880, 420)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let explorer = Explorer.create(window.documentPanel, window)
    window.explorer       = explorer
    window.explorerActive = true
    explorer.entries.add({name: "Film.mkv", size: 123, attempted: true,
                          movie: {title: "Film", director: "A director", overview: "A long synopsis"}})
    explorer.entries[0].technical.add(.Format, "Matroska")
    explorer.entries[0].technical.add(.Dimensions, "1920 × 1080 px")
    explorer.entries.add({name: "notes.txt", size: 10, attempted: true})
    explorer.fill()
    explorer.show()
    explorer.showInformation()
    window.applyLayout()
    explorer.grid.select(0)
    let sheet = window.infoSheet
    Swag.require(Utf8.contains(sheet.text(), "Director\nA director"))
    Swag.require(sheet.pageIndex == 0 and not Utf8.contains(sheet.text(), "Matroska"))
    sheet.selectPage(1)
    Swag.require(Utf8.contains(sheet.text(), "Technical\n") and Utf8.contains(sheet.text(), "1920 × 1080 px\n123 bytes"))
    Swag.require(Utf8.contains(sheet.text(), "File\nName\nFilm.mkv"))
    Swag.require(Utf8.contains(sheet.text(), "Format\nMatroska"))
    sheet.selectPage(0)
    Swag.require(not Utf8.contains(sheet.text(), "IMDb rating"))
    explorer.grid.select(1)
    Swag.require(not Utf8.contains(sheet.text(), "A director"))
    Swag.require(Utf8.contains(sheet.text(), "notes.txt"))
    sheet.close()
    Swag.require(not sheet.isLocallyVisible())
}

// The selected film keeps its media page when opened, while technical readings remain on the
// second page in both places.
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let video  = Path.combine(Path.combine(testSourceRoot(#curlocation), "datas"), "glint-aac-mjpeg.mp4")
    window.openExplorer(unwrap Path.directoryName(video))
    let explorer = unwrap window.explorer
    completeExplorer(&host, explorer)
    var selected = Swag.U64.Max
    for &entry, index in explorer.entries where entry.name == "glint-aac-mjpeg.mp4"
    {
        selected = index
        entry.movie.title = "Glint"
        entry.movie.director = "A director"
        entry.movie.overview = "A short film"
        entry.technical.add(.Format, "MPEG-4")
        break
    }

    Swag.require(selected != Swag.U64.Max)
    explorer.selected = selected
    window.toggleInformation()
    Swag.require(Utf8.contains(window.infoSheet.text(), "A short film"))
    window.infoSheet.selectPage(1)
    Swag.require(Utf8.contains(window.infoSheet.text(), "MPEG-4"))
    window.infoSheet.selectPage(0)

    explorer.activate(selected)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.infoSheet.isLocallyVisible() and window.infoSheet.pageIndex == 0)
    Swag.require(Utf8.contains(window.infoSheet.text(), "A short film"))
    window.infoSheet.selectPage(1)
    Swag.require(Utf8.contains(window.infoSheet.text(), "Frame rate"))
    Swag.require(not Utf8.contains(window.infoSheet.text(), "A short film"))
}
