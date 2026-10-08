#global using Core, Pixel, Gui

var g_App: Application

const ProductName   = "Swag Capture"
const ApplicationId = "swagcapture"
const SurfaceId     = "swag.capture"

// The message a second instance sends to the running one: open the image path it left on the
// clipboard.
const OpenImageMessage = 1'u32

#premain
{
    Reflection.registerType(#typeof(FormArrow))
    Reflection.registerType(#typeof(FormDraw))
    Reflection.registerType(#typeof(FormImage))
    Reflection.registerType(#typeof(FormLine))
    Reflection.registerType(#typeof(FormPolygon))
    Reflection.registerType(#typeof(FormShape))
    Reflection.registerType(#typeof(FormStep))
    Reflection.registerType(#typeof(FormText))
    Reflection.registerType(#typeof(FormCallout))
}

#main
{
    let args = Env.arguments()
    for arg in args where Path.isValidPathName(arg) and Image.canLoad(arg)
    {
        Clipboard.addString(arg)
        if Surface.sendCustomMessage(SurfaceId, OpenImageMessage, 0) do
            return
    }

    Swag.startWorkers()
    try Library.init()

    // Settings use a role-based file name so a product rename does not change their identity.
    g_App.setStatePath(Path.combine(Library.getDefaultFolder(), "settings.scc"))

    let appIcon = expect Image.decode(".png", AppIcon)
    g_App.setAppIcon(appIcon)
    registerAppStrings(&g_App.resources)

    let surface = try g_App.createSurface(0, 0, 10, 10, SurfaceFlags.StandardWindow, surfaceId: SurfaceId)
    g_App.theme.setSwagDark()
    g_App.notifyThemeChanged()
    let mainWnd = MainWnd.create(surface.wnd)

    if not Env.hasArgument("--hide") do
        surface.show()

    // Show the app icon in the notification area (system tray). Portable tray actions
    // are delivered to MainWnd.onSysUserEvent; the icon is removed automatically when
    // the surface is destroyed.
    surface.setTrayIcon(appIcon, ProductName)

    Env.registerApplication(ApplicationId, ProductName)
    Env.associateFileExtension(".png", ApplicationId, Env.executablePath())
    Env.associateFileExtension(".jpg", ApplicationId, Env.executablePath())

    for arg in args where Path.isValidPathName(arg) and Image.canLoad(arg)
    {
        mainWnd.loadExternalImage(arg)
        break
    }

    g_App.run()
}
