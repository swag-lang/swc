#global using Core, Pixel, Gui

const AppIcon = #include("../datas/appicon.png")

var g_App: Application

#main
{
    if isMountHostInvocation() do
        Env.exit(runMountHost())

    #static if #hastag("SVaultDrive.Integration")
    {
        if Integration.isVisibilityProbeInvocation() do
            Env.exit(Integration.runVisibilityProbe())
        Integration.runAndExit()
    }

    try Jobs.initialize()

    // Persisted window placement and browse-dialog state. A failure to prepare the
    // folder only costs the memory between runs, never the application start.
    let stateFolder = Path.combine(Env.getSpecialDirectory(.UserAppData), "sVaultDrive")
    if !Directory.exists(stateFolder) do
        discard catch Directory.create(stateFolder)
    if Directory.exists(stateFolder)
    {
        let statePath       = Path.combine(stateFolder, "sVaultDrive.scc")
        let previousPath    = Path.combine(stateFolder, "sVaultDrive.cfg")
        let legacyStatePath = Path.combine(Env.getSpecialDirectory(.UserAppData), "sCrypt", "sCrypt.cfg")
        let fallback        = File.exists(previousPath) ? previousPath : legacyStatePath
        if !File.exists(statePath) and File.exists(fallback) do
            discard catch File.duplicate(statePath, fallback)
        g_App.setStatePath(statePath)
    }

    let appIcon = expect Image.decode(".png", AppIcon)
    g_App.setAppIcon(appIcon)
    registerAppStrings(&g_App.resources)

    // Not a resizable window. The four pages hold a fixed number of fields, and the
    // strip already shows one at a time: there is nothing to gain room for, so a size grip and a
    // maximize button would only offer a window shape none of the pages is laid out for.
    const WindowFlags = SurfaceFlags.LargeCaption | SurfaceFlags.MinimizeButton | SurfaceFlags.CloseButton | SurfaceFlags.Border
    let surface = (try g_App.createSurface(80, 50, MainWindow.WindowWidth, MainWindow.WindowHeight, WindowFlags, surfaceId: "sVaultDrive"))!
    g_App.theme.setSwagDark()
    g_App.notifyThemeChanged()

    // English is the language sVaultDrive starts in. The window applies the persisted choice
    // once its state is restored, and says everything again in that language.
    surface.setTitle(appStrings().ui_WindowTitle)
    let mainWindow = MainWindow.create(surface.wnd)

    surface.show()
    discard g_App.run()
    mainWindow.shutdown()
}
