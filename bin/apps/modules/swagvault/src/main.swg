#global using Core, Pixel, Gui

const AppIcon = #include("../datas/appicon.png")

var g_App: Application

const ProductName = "Swag Vault"
const SurfaceId   = "swag.vault"

#main
{
    if isMountHostInvocation() do
        Env.exit(runMountHost())

    #static if #hastag("vault.integration")
    {
        if Integration.isVisibilityProbeInvocation() do
            Env.exit(Integration.runVisibilityProbe())
        Integration.runAndExit()
    }

    Swag.startWorkers()
    #static if #hastag("vault.hidden-copy")
    {
        discard catch runHiddenCopy() { Console.println(caughtMessage(Swag.err)) }
        Env.exit(copyError == null ? 0 : 1)
    }

    // Only non-sensitive preferences are persisted: no path is written while privacy mode is on.
    g_App.setAppIcon(expect Image.decode(".png", AppIcon))
    g_App.setStatePath(Path.combine(Env.getSpecialDirectory(.UserAppData), "Swag", "vault", "settings.scc"))
    registerAppStrings(&g_App.resources)

    // A standard window: the list of vaults grows downwards and the pages are measured columns,
    // so a taller or wider window only gives them air.
    let surface = try g_App.createSurface(80, 50, MainWindow.DefaultWidth, MainWindow.DefaultHeight, SurfaceFlags.StandardWindow, surfaceId: SurfaceId)
    g_App.theme.setDark()
    g_App.notifyThemeChanged()

    // English is the language Swag Vault starts in. The window applies the persisted choice
    // once its state is restored, and says everything again in that language.
    surface.setTitle(appStrings().ui_WindowTitle)
    let mainWindow = MainWindow.create(surface.wnd)

    surface.show()
    discard g_App.run()
    mainWindow.shutdown()
}
