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

// A picture that runs from `top` to `bottom`, standing for a thumbnail the renderer would make.
func boardPicture(width, height: s32, top, bottom: u32)->Image
{
    var bytes: Array'u8
    bytes.resize(cast(u64, width * height * 3))
    // The rows of an image run from the bottom up.
    for y in height
    {
        let t = cast(f32, height - 1 - y) / cast(f32, Math.max(height - 1, 1))
        for x in width
        {
            let at = cast(u64, (y * width + x) * 3)
            for channel in 3
            {
                let shift = cast(u32, (2 - channel) * 8)
                let a     = cast(f32, (top >> shift) & 0xFF)
                let b     = cast(f32, (bottom >> shift) & 0xFF)
                bytes[at + cast(u64, channel)] = cast(u8, Math.round(a + (b - a) * t))
            }
        }
    }

    return Image.create(width, height, .RGB8, bytes.toSlice())
}

// Builds the real window in the shipped frame, at the size of the pictures, its explorer showing
// `entries` under the title `folder` beside the path `parent`.
func boardWindow(host: *Testing.HeadlessHost, light: bool, films: bool)->*ViewerWindow
{
    host.setup(1280, 800)
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
func showBoard(host: *Testing.HeadlessHost, window: *ViewerWindow, parent, folder: string)
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

// Adds an entry with a picture already rendered for it.
func addPictured(host: *Testing.HeadlessHost, explorer: *Explorer, name: string, picture: Image, size: u64, duration = 0'u64)
{
    with var entry: ExplorerEntry
    {
        .name      = name
        .path      = name
        .size      = size
        .duration  = duration
        .attempted = true
    }

    entry.texture = host.app.renderer.addImage(&picture)
    explorer.entries.add(#move entry)
}

// A mixed folder: every cell the same shape, a picture filling its cell, a film with its length
// in a chip, a folder with its count, anything without a picture the faint page of its kind with
// its extension; the name, then one mono line of facts.
#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        let window   = boardWindow(&host, light, films: false)
        let explorer = unwrap window.explorer
        explorer.entries.add({name: "Captures", path: "Captures", directory: true, children: 24, attempted: true})
        explorer.entries.add({name: "Exports", path: "Exports", directory: true, children: 6, attempted: true})
        addPictured(&host, explorer, "dune-poster.png", boardPicture(160, 100, 0x9A5F2E, 0xE0A266), 412 * 1024)
        addPictured(&host, explorer, "lens-demo.mp4", boardPicture(192, 108, 0x24456E, 0x3D6C9E), 24 * 1024 * 1024, 161)
        for name, size in ["annual-report.pdf", "explorer.swg", "voice-over.flac", "design.silence.md"] do
            explorer.entries.add({name: name, path: name, size: 2048 * (size + 1), attempted: true})

        // What the listing reads of each file, as it would of the real ones.
        let at = explorer.entries.count
        explorer.entries[at - 4].pages = 12
        with let code = &explorer.entries[at - 3]
        {
            .lines   = 214
            .excerpt = "impl Explorer\n{\n    mtd layout()\n    {\n        let cells = .cells\n        for c in cells do\n            c.fit()\n"
        }

        with let markdown = &explorer.entries[at - 1]
        {
            .sections = 3
            .excerpt  = "# Silence\nThe window shows the document and nothing else.\nEvery command is an entry of the lens.\n\n## Motion\nWhat floats arrives and leaves.\n"
        }

        addPictured(&host, explorer, "forest.jpg", boardPicture(160, 120, 0x2F4A32, 0x7FA36A), 3 * 1024 * 1024)
        for name, size in ["vault.bin", "Inter-Light.ttf", "sources.zip"] do
            explorer.entries.add({name: name, path: name, size: 1024 * 1024 * (size + 1), attempted: true})
        explorer.entries[2].width  = 800
        explorer.entries[2].height = 500
        explorer.entries[8].width  = 4032
        explorer.entries[8].height = 3024
        explorer.entries[10].face  = "Inter · Light"
        explorer.entries[11].members = 48
        explorer.selected = 3
        showBoard(&host, window, "Documents", "Projects")

        // Every tile has the same size and the grid fills the page between its margins.
        let grid = explorer.grid
        Swag.assert(not grid.posters and grid.columns == 6)
        Swag.assert(grid.tileRect(1).x - grid.tileRect(0).right() == ExplorerGrid.Gap)
        Swag.assert(not explorer.filter.isLocallyVisible())
        var image = host.render(window)
        Pixel.Testing.assertImageGolden(&image, light ? "explorer.mixed.paper" : "explorer.mixed")

        // The view menu can force a shape, and give it back to what the folder holds.
        explorer.forceBoard(true, .Mosaic)
        Swag.assert(grid.board == .Mosaic and explorer.modeMenu.name.raw == appStrings().mode_Mosaic)
        explorer.forceBoard(false)
        Swag.assert(grid.board == .Grid)
    }
}

// A folder of films: upright posters in their own shape, title then year and length, and the
// sheet headed by the poster beside the title, the year and length, and the rating.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window   = boardWindow(&host, false, films: true)
    let explorer = unwrap window.explorer
    let names:   [8] string = ["Blade Runner", "Alien", "Arrival", "Dune", "Heat", "Drive", "Stalker", "Gattaca"]
    let years:   [8] string = ["1982", "1979", "2016", "2021", "1995", "2011", "1979", "1997"]
    let lengths: [8] u64    = [117, 117, 116, 155, 170, 100, 162, 106]
    let tops:    [8] u32    = [0x141A3C, 0x0A0F0C, 0xD2D4D4, 0xE8B27A, 0x26385A, 0x200C1A, 0x6E6C48, 0x1C4A44]
    let bottoms: [8] u32    = [0xC2561E, 0x2B3D2C, 0x3A3D40, 0x7A4A20, 0x16223A, 0xE0508E, 0x44442C, 0xD8B460]
    for name, index in names
    {
        let file = Format.toString("%.mkv", name)
        addPictured(&host, explorer, file, boardPicture(120, 176, tops[index], bottoms[index]), 8 * 1024 * 1024 * 1024, lengths[index] * 60)
        let last = explorer.entries.count - 1
        explorer.entries[last].movie.title = name
        explorer.entries[last].movie.date  = years[index]
    }

    with let first = &explorer.entries[0]
    {
        .movie.imdbRating = "8.1/10"
        .movie.director   = "Ridley Scott"
        .movie.actors     = "Harrison Ford, Rutger Hauer"
        .movie.overview   = "A science-fiction film directed by Ridley Scott, adapted from the novel by Philip K. Dick."
        .movie.sources    = "Apple · Wikipedia · Wikidata"
    }

    explorer.selected = 0
    showBoard(&host, window, "Videos", "Films")
    explorer.showInformation()
    window.applyLayout()
    host.settleAnimations(window)

    let grid = explorer.grid
    Swag.assert(grid.posters and grid.tile.y > grid.tile.x)
    Swag.assert(window.infoSheet.beside and Utf8.contains(window.infoSheet.text(), "1982 · 117 min"))
    Swag.assert(grid.tileRect(0).right() < window.infoSheet.surfaceRect().x)
    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "explorer.films")
}

// A music library: square covers, the album, then who made it and when in mono.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window   = boardWindow(&host, false, films: false)
    let explorer = unwrap window.explorer
    let albums:  [8] string = ["Discovery", "Random Access Memories", "In Rainbows", "Kid A", "Moon Safari", "Homework", "Currents", "Blue Lines"]
    let artists: [8] string = ["Daft Punk", "Daft Punk", "Radiohead", "Radiohead", "Air", "Daft Punk", "Tame Impala", "Massive Attack"]
    let years:   [8] string = ["2001", "2013", "2007", "2000", "1998", "1997", "2015", "1991"]
    let tops:    [8] u32    = [0x2A1A4A, 0x2A2418, 0xF0B050, 0xD8E2EA, 0xEDE6D2, 0x141414, 0x4A2A6A, 0x14305A]
    let bottoms: [8] u32    = [0xD8508A, 0xC8A040, 0xE04848, 0x5A7A96, 0x7A98C0, 0x3A3A3A, 0xE07038, 0x3A78C0]
    for album, index in albums
    {
        addPictured(&host, explorer, Format.toString("%.flac", album), boardPicture(96, 96, tops[index], bottoms[index]), 30 * 1024 * 1024)
        let last = explorer.entries.count - 1
        explorer.entries[last].music = {title: album, artist: artists[index], date: years[index]}
    }

    explorer.selected = 0
    showBoard(&host, window, "Music", "Albums")
    let grid = explorer.grid
    Swag.assert(grid.board == .Covers and grid.tile.x == grid.tile.y)
    Swag.assert(Utf8.startsWith(explorer.status.text(), Format.toString("% · %", Format.toString(appStrings().explore_Albums, 8), Format.toString(appStrings().explore_Tracks, 8))))
    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "explorer.music")
}

// One album: its cover large with Play and Shuffle, then its kind and year, its title, who made
// it, its facts, and its tracks with their lengths in mono, the chosen one led by ▶ on the Arc ground.
#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        let window   = boardWindow(&host, light, films: false)
        let explorer = unwrap window.explorer
        let tracks:  [10] string = ["One More Time", "Aerodynamic", "Digital Love", "Harder, Better, Faster, Stronger", "Crescendolls",
                                    "Nightvision", "Superheroes", "High Life", "Something About Us", "Voyager"]
        let lengths: [10] u64    = [320, 207, 298, 224, 211, 104, 237, 201, 231, 227]
        for track, index in tracks
        {
            let file = Format.toString("%{02} - %.flac", index + 1, track)
            if index == 0 do
                addPictured(&host, explorer, file, boardPicture(120, 120, 0x24184A, 0xD8508A), 30 * 1024 * 1024, lengths[index])
            else do
                explorer.entries.add({name: file, path: file, size: 30 * 1024 * 1024, duration: lengths[index], attempted: true})
            let last = explorer.entries.count - 1
            explorer.entries[last].music = {title: "Discovery", artist: "Daft Punk", date: "2001-03-12"}
        }

        explorer.selected = 2
        showBoard(&host, window, "Music / Daft Punk", "Discovery")
        let grid = explorer.grid
        Swag.assert(grid.board == .Album and grid.playButton!.isLocallyVisible() and not explorer.title.isLocallyVisible())
        Swag.assert(trackTitle("03 - Digital Love.flac") == "Digital Love")
        var image = host.render(window)
        Pixel.Testing.assertImageGolden(&image, light ? "explorer.album.paper" : "explorer.album")
    }
}

// Photographs: a justified mosaic that keeps every shape, a day after another under its label
// and its count.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window   = boardWindow(&host, false, films: false)
    let explorer = unwrap window.explorer
    let widths:  [12] s32 = [180, 150, 96, 180, 150, 150, 180, 120, 96, 200, 150, 150]
    let heights: [12] s32 = [96, 100, 128, 96, 100, 100, 100, 100, 128, 100, 100, 100]
    let tops:    [12] u32 = [0x34452E, 0xC88A48, 0x203050, 0x4A2A2A, 0x7090B8, 0x222222, 0x305050, 0x9A6A34, 0x1C4A44, 0x24385A, 0x4A3A24, 0x5A3A7A]
    let bottoms: [12] u32 = [0x7AA06A, 0xF0D098, 0x4A6A9A, 0xB0645A, 0xEAE4D8, 0x4A4A4A, 0x98C0B8, 0xE0A060, 0xD8B460, 0x8AB0D8, 0xB89A70, 0xD898C8]
    for i in 12
    {
        addPictured(&host, explorer, Format.toString("IMG_20%.jpg", 41 + i), boardPicture(widths[i], heights[i], tops[i], bottoms[i]), 4 * 1024 * 1024)
        explorer.entries[explorer.entries.count - 1].modified = i < 8 ? "2026-10-21 10:00" : "2026-10-22 10:00"
    }

    explorer.selected = 2
    showBoard(&host, window, "Pictures", "Brittany 2026")
    let grid = explorer.grid

    // What is known of the picture under the pointer stands in a mono tip over it.
    grid.hovered = 5
    grid.invalidate()
    Swag.assert(Utf8.startsWith(explorer.status.text(), Format.toString(appStrings().explore_Photos, 12)))
    Swag.assert(grid.board == .Mosaic and grid.days.count == 2 and grid.days[0].count == 8)
    Swag.assert(grid.days[0].text == "Wednesday 21 October")
    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "explorer.photos")
}

// The listing reads what a cell shows of a file: the size of a picture from its head, the pages of
// a document, the lines and first lines of code, the sections of Markdown, a font's face.
#test
{
    let folder = Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas")
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
