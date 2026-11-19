#global using Core, Pixel, Gui

const AppIcon = #include("../datas/appicon.png")

var g_App: Application

const ProductName       = "Swag Vault"
const SurfaceId         = "swag.vault"
const ShowWindowMessage = 1'u32
const ApplicationId     = "swagvault"

#main
{
    if isMountHostInvocation() do
        Env.exit(runMountHost())

    #static if #hastag("vault.integration")
    {
        if Integration.isVisibilityProbeInvocation() do
            Env.exit(Integration.runVisibilityProbe())
        if Integration.isAccessBenchmarkInvocation() do
            Integration.runAccessBenchmarkAndExit()
        if Integration.isPreviewMountInvocation() do
            Integration.runPreviewMountAndExit()
        Integration.runAndExit()
    }

    #static if #hastag("vault.hidden-copy")
    {
        var copyErrorOutcome: Swag.Error
        discard catch runHiddenCopy() as copyErrorOutcome { Console.println(caughtMessage(Swag.err)) }
        let copyError = copyErrorOutcome.value()
        Env.exit(copyError == null ? 0 : 1)
    }

    let launchFile = vaultLaunchFile(Env.arguments())
    var instance: Env.SessionInstance

    // A sandboxed smoke has its own state and must never wake the user's running window.
    let surfaceId = Format.toString("%.%", SurfaceId, Hash.hash64(Env.getSpecialDirectory(.UserAppData)))
    if not try instance.acquire(ApplicationId)
    {
        // The first instance may still be constructing its surface after acquiring presence.
        if launchFile.isEmpty()
        {
            for 250
            {
                if Surface.sendCustomMessage(surfaceId, ShowWindowMessage, 0) do
                    return
                Threading.Thread.sleep(20'ms)
            }
        }
        elif try forwardVaultLaunch(surfaceId, launchFile)
        {
            return
        }

        fail Swag.SystemError{"the running Swag Vault instance did not respond"}
    }

    // Only non-sensitive preferences are persisted: no path is written while privacy mode is on.
    g_App.setAppIcon(expect Image.decode(".png", AppIcon))
    g_App.setStatePath(Path.combine(Env.getSpecialDirectory(.UserAppData), "Swag", "vault", "settings.scc"))
    registerAppStrings(&g_App.resources)

    // A standard window: the list of vaults grows downwards and the pages are measured columns,
    // so a taller or wider window only gives them air.
    let surface = try g_App.createSurface(80, 50, MainWindow.DefaultWidth, MainWindow.DefaultHeight, SurfaceFlags.StandardWindow, surfaceId: surfaceId)
    g_App.theme.setDark()
    g_App.notifyThemeChanged()

    // English is the language Swag Vault starts in. The window applies the persisted choice
    // once its state is restored, and says everything again in that language.
    surface.setTitle(appStrings().ui_WindowTitle)
    let mainWindow = MainWindow.create(surface.wnd)

    mainWindow.initialize()
    if not launchFile.isEmpty()
    {
        mainWindow.resident.activate()
        mainWindow.queueAutomaticMount(launchFile)
    }

    mainWindow.resident.start()
    discard g_App.run()
}
