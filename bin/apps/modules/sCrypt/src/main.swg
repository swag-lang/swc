#global using Core, Pixel, Gui

const AppIcon = #include("../datas/appicon.png")

var g_App: Application

#main
{
    if WinFsp.isPortableGuardianInvocation() do
        Env.exit(WinFsp.runPortableGuardian())

    #static if #hastag("SCrypt.Integration")
    {
        if Integration.isVisibilityProbeInvocation() do
            Env.exit(Integration.runVisibilityProbe())
        Integration.runAndExit()
    }

    StartupTrace.mark("#main enter")
    try Jobs.initialize()
    StartupTrace.mark("Jobs.initialize (main)")

    // Persisted window placement and browse-dialog state. A failure to prepare the
    // folder only costs the memory between runs, never the application start.
    let stateFolder = Path.combine(Env.getSpecialDirectory(.UserAppData), "sCrypt")
    if !Directory.exists(stateFolder) do
        discard catch Directory.create(stateFolder)
    if Directory.exists(stateFolder) do
        g_App.setStatePath(Path.combine(stateFolder, "sCrypt.cfg"))

    let appIcon = expect Image.decode(".png", AppIcon)
    g_App.setAppIcon(appIcon)
    StartupTrace.mark("app icon decode")
    let surface = (try g_App.createSurface(80, 50, 1100, 790, SurfaceFlags.StandardWindow, surfaceId: "sCrypt"))!
    g_App.theme.setSwagDark()
    g_App.notifyThemeChanged()
    surface.setTitle("sCrypt — Private virtual drives")
    StartupTrace.mark("setSwagDark+notifyThemeChanged")
    let mainWindow = MainWindow.create(surface.wnd)
    StartupTrace.mark("MainWindow.create")

    surface.show()
    StartupTrace.mark("surface.show")
    StartupTrace.flush()
    discard g_App.run()
    mainWindow.shutdown()
}
