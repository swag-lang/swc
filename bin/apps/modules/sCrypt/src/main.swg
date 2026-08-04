using Core, Gui, Pixel

const AppIcon = #include("../datas/appicon.png")

var g_App: Application

#main
{
    if SCrypt.Platform.isPortableGuardianInvocation() do
        Env.exit(SCrypt.Platform.runPortableGuardian())

    #static if #hastag("SCrypt.Integration")
    {
        if SCrypt.Integration.isVisibilityProbeInvocation() do
            Env.exit(SCrypt.Integration.runVisibilityProbe())
        SCrypt.Integration.runAndExit()
    }

    try Jobs.initialize()

    let appIcon = expect Image.decode(".png", AppIcon)
    g_App.setAppIcon(appIcon)
    let surface = notnull (try g_App.createSurface(80, 50, 1100, 790, SurfaceFlags.StandardWindow, surfaceId: "sCrypt"))
    g_App.theme.setSwagDark()
    g_App.notifyThemeChanged()
    surface.setTitle("sCrypt — Private virtual drives")
    let mainWindow = MainWindow.create(surface.wnd)

    surface.show()
    discard g_App.run()
    mainWindow.shutdown()
}
