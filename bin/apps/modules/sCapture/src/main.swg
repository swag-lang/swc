#global using Core, Pixel, Gui

var g_App: Application

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

    Reflection.registerTypeAlias(0x0A77C1A5, #typeof(FormPolygon))
    Reflection.registerTypeAlias(0x0B61E593, #typeof(FormLine))
    Reflection.registerTypeAlias(0xAA87EC6A, #typeof(FormDraw))
    Reflection.registerTypeAlias(0xE0321F5E, #typeof(FormShape))
    Reflection.registerTypeAlias(0xE1FEF6A2, #typeof(FormText))
    Reflection.registerTypeAlias(0xE5350EB8, #typeof(FormArrow))
    Reflection.registerTypeAlias(0xF83FE4D9, #typeof(FormImage))
}

#main
{
    let args = Env.arguments()
    for arg in args
    {
        if !Path.isValidPathName(arg) do
            continue
        if !Image.canLoad(arg) do
            continue
        Clipboard.addString(arg)
        if Surface.sendCustomMessage("sCapture", 1, 0) do
            return
    }

    try Jobs.initialize()
    try Library.init()

    let path = Path.combine(Library.getFolder(), "sCapture.cfg")
    g_App.setStatePath(path)

    let appIcon = expect Image.decode(".png", AppIcon)
    g_App.setAppIcon(appIcon)
    registerAppStrings(&g_App.resources)

    let surface = (try g_App.createSurface(0, 0, 10, 10, SurfaceFlags.StandardWindow, surfaceId: "sCapture"))!
    g_App.theme.setSwagDark()
    g_App.notifyThemeChanged()
    let mainWnd = MainWnd.create(surface.wnd)

    if !Env.hasArgument("--hide") do
        surface.show()

    // Show the app icon in the notification area (system tray). Right-clicking it
    // is delivered to MainWnd.onSysUserEvent as a WM_USER event; the icon is removed
    // automatically when the surface is destroyed.
    surface.setTrayIcon(appIcon, "sCapture")

    with Env
    {
        .registerApplication("sCapture", "sCapture")
        .associateFileExtension(".png", "sCapture", Env.executablePath())
        .associateFileExtension(".jpg", "sCapture", Env.executablePath())
    }

    for arg in args
    {
        if !Path.isValidPathName(arg) do
            continue
        if !Image.canLoad(arg) do
            continue
        Console.print(arg)
        mainWnd.loadExternalImage(arg)
        break
    }

    g_App.run()
}
