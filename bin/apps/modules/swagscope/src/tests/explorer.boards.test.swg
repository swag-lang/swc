#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

// Waits for the explorer's listing, letting the window take what it published.
func settleBoardListing(host: *Testing.HeadlessHost, explorer: *Explorer)
{
    for 16
    {
        if not explorer.load.started do
            return
        explorer.load.task.wait()
        host.pump()
    }

    Swag.assert(false, "exploration did not settle")
}

// Builds the real window in the shipped frame, at the size of the pictures, its explorer showing
// `entries` under the title `folder` beside the path `parent`.
internal func boardWindow(host: *Testing.HeadlessHost, light: bool, films: bool, scale = 1.0, width = 1280, height = 800)->*ViewerWindow
{
    host.setup(width, height, scale)
    registerAppStrings(&host.app.resources)
    host.surface.updateFlags(SurfaceFlags.StandardWindow | SurfaceFlags.NoShadow)
    if light do
        host.theme.setLight()
    else do
        host.theme.setDark()
    host.notify(.ThemeChanged)

    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.onlineMovies = films
    window.onlineMusic  = false
    window.openExplorer(Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas"))
    let explorer = unwrap window.explorer
    settleBoardListing(host, explorer)

    // The previews of the real folder are retired before the board takes its place: none of them
    // may publish into the entries the test puts there.
    explorer.suspend()
    for &preview in explorer.previews do
        preview.wait()
    explorer.generation += 1
    explorer.entries.clear()
    return window
}

// Shows what the test put in the explorer, as its page.
internal func showBoard(host: *Testing.HeadlessHost, window: *ViewerWindow, parent, folder: string)
{
    let explorer = unwrap window.explorer
    explorer.address.breadcrumb.clear()
    explorer.address.breadcrumb.addItem(parent)
    explorer.address.refreshPath()
    explorer.title.setText(folder)
    explorer.setMode(.Medium)
    explorer.fill()
    explorer.title.setText(folder)
    explorer.layoutTools()
    window.applyLayout()
    host.settleAnimations(window)
}

// The same view command acts from the lens and the menu; Covers and Posters must not trade places.
#test
{
    var host: Testing.HeadlessHost
    let window   = boardWindow(&host, false, films: false)
    let explorer = unwrap window.explorer
    explorer.entries.add({name: "notes.txt", path: "notes.txt", attempted: true})
    explorer.fill()
    for language in [ReferenceLanguage, "fr"]
    {
        expect host.app.setLanguage(language)
        host.notify(.LanguageChanged)
        for command, index in ViewerCommands.Boards
        {
            window.sendCommandEvent(command)
            let state = window.sendComputeCommandStateEvent(command)
            Swag.assert(state.checked and not state.hidden and not state.disabled)
            Swag.assert(explorer.forced == (index != 0))
            if index do
                Swag.assert(cast(u64, explorer.forcedBoard) == index - 1)
            if index == 2 do
                Swag.assert(state.name == appStrings().board_Posters and explorer.grid.board == .Posters)
            if index == 3 do
                Swag.assert(state.name == appStrings().board_Covers and explorer.grid.board == .Covers)
            if index == 4 do
                Swag.assert(state.name == appStrings().board_Mosaic and explorer.grid.board == .Mosaic)
            window.lens.open(state.name)
            var found = false
            for section in window.lens.results.sections
            {
                for entry in section!.entries where entry.id == command do
                    found = true
            }

            Swag.assert(found)
            window.lens.close()
        }

        for command, index in ViewerCommands.Artwork
        {
            window.sendCommandEvent(command)
            let state = window.sendComputeCommandStateEvent(command)
            Swag.assert(state.checked and not state.hidden and not state.disabled)
            Swag.assert(cast(u64, explorer.artworkSource) == index)
        }

        for command, index in ViewerCommands.Modes
        {
            window.sendCommandEvent(command)
            Swag.assert(cast(u64, explorer.mode) == index)
            Swag.assert(window.sendComputeCommandStateEvent(command).checked)
            for board in ViewerCommands.Boards
            {
                let state = window.sendComputeCommandStateEvent(board)
                Swag.assert(state.hidden == (index < cast(u64, ExplorerMode.Small)))
            }
        }

        explorer.entries.add({name: "Film.mkv", path: "Film.mkv", attempted: true})
        window.onlineMovies = true
        window.onlineMusic  = true
        explorer.setKindFilter(.Videos)
        explorer.forceBoard(true, .Grid)
        explorer.setArtworkSource(.Local)
        let localSettings = expect ThumbnailSettings.decode(explorer.previewSettings)
        Swag.assert(explorer.grid.board == .Grid and explorer.previewAspect == ExplorerFilmPreviewAspect)
        Swag.assert(localSettings.onlineMovies and localSettings.onlineMusic and localSettings.localArtworkOnly)
        explorer.setArtworkSource(.Online)
        let onlineSettings = expect ThumbnailSettings.decode(explorer.previewSettings)
        Swag.assert(not onlineSettings.localArtworkOnly)
        let folder = unwrap Path.directoryName(#curlocation.fileName)
        let audio  = Path.combine(folder, "song.flac")
        let video  = Path.combine(folder, "datas", "rv40-legacy-clock.mkv")
        Swag.assert(onlinePreviewWanted(audio, &onlineSettings) and onlinePreviewWanted(video, &onlineSettings))
        onlineSettings.localArtworkOnly = true
        Swag.assert(not onlinePreviewWanted(audio, &onlineSettings) and not onlinePreviewWanted(video, &onlineSettings))
    }
}

// Albums stored as directories take the same cover board and open into their track pages.
#test
{
    let root = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-library-%", Guid64.random()))
    expect Directory.create(root)
    defer catch Directory.delete(root, recurse: true)
    for name in ["Discovery", "In Rainbows"]
    {
        let album = Path.combine(root, name)
        expect Directory.create(album)
        for index in 2 do
            discard expect File.writeAllText(Path.combine(album, Format.toString("%.flac", index)), "fixture")
    }

    var listing = expect ExplorerListing.load(root)
    Swag.assert(listing.entries.count == 2)
    for &entry in listing.entries do
        Swag.assert(entry.directory and not entry.albumTrack.isEmpty() and entry.music.title == entry.name)

    var host: Testing.HeadlessHost
    let window   = boardWindow(&host, false, films: false)
    let explorer = unwrap window.explorer
    explorer.entries = #move listing.entries
    showBoard(&host, window, "Music", "Albums")
    Swag.assert(explorer.grid.board == .Covers)
    Swag.assert(Utf8.startsWith(explorer.status.text(), Format.toString(appStrings().explore_Albums, 2)))
}

// The listing reads what a cell shows of a file: the size of a picture from its head, the pages of
// a document, the lines and first lines of code, the sections of Markdown, a font's face.
#test
{
    let folder  = Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas")
    var picture = ExplorerEntry{name: "title.png", path: Path.combine(folder, "title.png")}
    var pdf     = ExplorerEntry{name: "viewer.pdf", path: Path.combine(folder, "viewer.pdf")}
    var code    = ExplorerEntry{name: "sample.cpp", path: Path.combine(folder, "sample.cpp")}
    var notes   = ExplorerEntry{name: "comprehensive.md", path: Path.combine(folder, "comprehensive.md")}
    var font    = ExplorerEntry{name: "segoeui.ttf", path: Path.combine(folder, "segoeui.ttf")}
    var archive = ExplorerEntry{name: "viewer.archive.zip", path: Path.combine(folder, "viewer.archive.zip")}
    var other   = ExplorerEntry{name: "notes.bin", path: Path.combine(folder, "notes.bin")}
    Swag.assert(probeEntry(&archive) and archive.members >= 2)
    Swag.assert(probeEntry(&picture) and picture.width > 0 and picture.height > 0)
    Swag.assert(probeEntry(&pdf) and pdf.pages >= 1)
    Swag.assert(probeEntry(&code) and code.lines > 1 and not code.excerpt.isEmpty())
    Swag.assert(probeEntry(&notes) and notes.sections >= 1)
    Swag.assert(probeEntry(&font) and Utf8.contains(font.face.toString(), "Segoe"))
    Swag.assert(not probeEntry(&other))
}
