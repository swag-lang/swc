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
        discard catch runHiddenCopy() as copyError
        if copyError != null do
            Console.println("Copy stopped: ", Errors.message(copyError))
        Env.exit(copyError == null ? 0 : 1)
    }

    // Only non-sensitive preferences are persisted: no path is written while privacy mode is on.
    g_App.setAppIcon(expect Image.decode(".png", AppIcon))
    g_App.setStatePath(Path.combine(Env.getSpecialDirectory(.UserAppData), "Swag", "vault", "settings.scc"))
    registerAppStrings(&g_App.resources)

    // Not a resizable window. The four pages hold a fixed number of fields, and the
    // strip already shows one at a time: there is nothing to gain room for, so a size grip and a
    // maximize button would only offer a window shape none of the pages is laid out for.
    const WindowFlags = SurfaceFlags.LargeCaption |
                        SurfaceFlags.MinimizeButton |
                        SurfaceFlags.CloseButton |
                        SurfaceFlags.Border

    // Start with a width for wrapping; MainWindow measures the final height before showing.
    let surface = try g_App.createSurface(80, 50, MainWindow.WindowWidth, MainWindow.WindowWidth, WindowFlags, surfaceId: SurfaceId)
    g_App.theme.setSwagDark()
    g_App.notifyThemeChanged()

    // English is the language Swag Vault starts in. The window applies the persisted choice
    // once its state is restored, and says everything again in that language.
    surface.setTitle(appStrings().ui_WindowTitle)
    let mainWindow = MainWindow.create(surface.wnd)

    surface.show()
    discard g_App.run()
    mainWindow.shutdown()
}
