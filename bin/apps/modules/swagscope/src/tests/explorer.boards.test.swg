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
        addPictured(&host, explorer, "forest.jpg", boardPicture(160, 120, 0x2F4A32, 0x7FA36A), 3 * 1024 * 1024)
        for name, size in ["vault.bin", "Inter-Light.ttf", "sources.zip"] do
            explorer.entries.add({name: name, path: name, size: 1024 * 1024 * (size + 1), attempted: true})
        explorer.selected = 3
        showBoard(&host, window, "Documents", "Projects")

        // Every tile has the same size and the grid fills the page between its margins.
        let grid = explorer.grid
        Swag.assert(not grid.posters and grid.columns == 6)
        Swag.assert(grid.tileRect(1).x - grid.tileRect(0).right() == ExplorerGrid.Gap)
        Swag.assert(not explorer.filter.isLocallyVisible())
        var image = host.render(window)
        Pixel.Testing.assertImageGolden(&image, light ? "explorer.mixed.paper" : "explorer.mixed")
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
