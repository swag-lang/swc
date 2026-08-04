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

    try Jobs.initialize()

    let appIcon = expect Image.decode(".png", AppIcon)
    g_App.setAppIcon(appIcon)
    registerAppStrings(&g_App.resources)

    let surface = notnull (try g_App.createSurface(80, 50, 1100, 790, SurfaceFlags.StandardWindow, surfaceId: "sCrypt"))
    g_App.theme.setSwagDark()
    g_App.notifyThemeChanged()

    // Follow the user's system language when a translation ships for it.
    if Utf8.startsWith(Env.userLocaleName().toString(), "fr") do
        catch g_App.setLanguage("fr")

    surface.setTitle(appStrings().ui_WindowTitle)
    let mainWindow = MainWindow.create(surface.wnd)

    surface.show()
    discard g_App.run()
    mainWindow.shutdown()
}
