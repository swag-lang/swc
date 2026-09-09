#global using Core, Pixel, Gui

const AppIcon = #include("../datas/appicon.png")

var g_App: Application

const ProductName = "Swag Prism"
const SurfaceId   = "swag.prism"

#main
{
    // The theme atlas and the editor's own measurement work fan through the runtime's shared
    // worker pool, and so does the compilation the window runs off its own thread. Starting it
    // here keeps that cost out of the first compilation.
    Swag.startWorkers()

    let appIcon = expect Image.decode(".png", AppIcon)
    g_App.setAppIcon(appIcon)
    registerAppStrings(&g_App.resources)

    let stateRoot = Path.combine(Env.getSpecialDirectory(.UserAppData), "Swag")
    if !Directory.exists(stateRoot) do
        discard catch Directory.create(stateRoot)
    let stateFolder = Path.combine(stateRoot, "prism")
    if !Directory.exists(stateFolder) do
        discard catch Directory.create(stateFolder)
    if Directory.exists(stateFolder)
    {
        g_App.setStatePath(Path.combine(stateFolder, "settings.scc"))
    }

    let surface = (try g_App.createSurface(80, 50, MainWindow.WindowWidth, MainWindow.WindowHeight, SurfaceFlags.StandardWindow, surfaceId: SurfaceId))!
    g_App.theme.setSwagDark()
    g_App.notifyThemeChanged()
    surface.setTitle(appStrings().ui_WindowTitle)

    let window = MainWindow.create(surface.wnd)

    // The persisted palette and language are applied while the window is still hidden, so the
    // first frame is already the one the reader chose rather than the shipped default.
    window.applyTheme()
    window.applyLanguage()

    surface.show()
    window.compile()

    let exitCode = g_App.run()
    window.shutdown()
    if exitCode do
        Env.exit(exitCode)
}
