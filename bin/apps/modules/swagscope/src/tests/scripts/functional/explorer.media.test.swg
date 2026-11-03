#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

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
    Swag.assert(host.autoHandled and musicChoiceId(window.musicChoices.toSlice(), &explorer.entries[1]) == id)
    Swag.assert(explorer.generation > generation)
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
    Swag.assert(not music.hidden and music.updatedFields.has(.Checked) and not music.checked)
    Swag.assert(window.sendComputeCommandStateEvent(ViewerCommands.ChooseMusic).disabled)
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
        Swag.assert(window.infoSheet.isVisible())
        Swag.assert(window.infoSheet.position.bottom() <= window.clientRect().bottom())
        Swag.assert(explorer.grid.clientRect().height > 150)
    }
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
    explorer.entries.add({name: "notes.txt", size: 10, attempted: true})
    explorer.fill()
    explorer.show()
    explorer.showInformation()
    window.applyLayout()
    explorer.grid.select(0)
    let sheet = window.infoSheet
    Swag.assert(Utf8.contains(sheet.text(), "Director\nA director"))
    Swag.assert(not Utf8.contains(sheet.text(), "IMDb rating"))
    explorer.grid.select(1)
    Swag.assert(not Utf8.contains(sheet.text(), "A director"))
    Swag.assert(Utf8.contains(sheet.text(), "notes.txt"))
    sheet.close()
    Swag.assert(not sheet.isLocallyVisible())
}
