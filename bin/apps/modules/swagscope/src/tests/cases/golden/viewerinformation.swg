#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Audio

// A film's media page stays centred in the viewing area with a stable panel height in Encre.
#[Swag.TestTag("golden")]
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, picturedFixture("glint-aac-mjpeg.mp4"), false, 960, 640)
    window.onlineMovies = false
    window.toggleInformation()
    completeInformation(&host, window)
    let view = assume cast(*Viewers.Film.Panel, window.currentView)
    pinVideoFrame(view, 0)
    window.information.entry.movie = {title: "Northbound", date: "2024", imdbRating: "8.1/10",
                                      overview: "A quiet journey through the northern coast.",
                                      director: "Avery Morgan", actors: "Alex Rivera, Robin Blake", sources: "Apple"}
    window.information.entry.modified = "2026-01-01 12:00"
    window.information.describe(window.infoSheet)
    window.layoutFloatingParts()
    photographViewer(&host, window, "viewer.information.movie.encre")
}

// A recording's technical page shares the same placement, with the player remaining visible in Papier.
#[Swag.TestTag("golden")]
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, picturedFixture("pacman_beginning.wav"), true, 960, 640)
    window.onlineMusic = false
    window.toggleInformation()
    completeInformation(&host, window)
    window.information.entry.modified = "2026-01-01 12:00"
    window.information.describe(window.infoSheet)
    window.infoSheet.selectPage(1)
    window.layoutFloatingParts()
    photographViewer(&host, window, "viewer.information.sound.papier")
}

// Full-screen information leaves the complete transport usable and keeps both vertical margins.
#[Swag.TestTag("golden")]
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, picturedFixture("glint-aac-mjpeg.mp4"), true, 960, 640)
    window.onlineMovies = false
    window.toggleInformation()
    completeInformation(&host, window)
    pinVideoFrame(assume cast(*Viewers.Film.Panel, window.currentView), 0)
    window.information.entry.movie    = {title: "Northbound", date: "2024"}
    window.information.entry.modified = "2026-01-01 12:00"
    window.information.describe(window.infoSheet)
    window.infoSheet.selectPage(1)
    let viewport = host.surface.position
    window.setFullScreen(true)
    host.surface.showNormalAt(viewport)
    window.applyLayout()
    window.revealViewerBar()
    window.layoutFloatingParts()
    let inset = window.themeMetrics().floating_Inset
    Swag.require(window.infoSheet.position.bottom() + inset <= window.viewerBar.position.y)
    photographViewer(&host, window, "viewer.information.fullscreen.papier")
}
