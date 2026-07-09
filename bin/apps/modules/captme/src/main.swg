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

    Reflection.registerCrcToTypeAlias(0x0A77C1A5, #typeof(FormPolygon))
    Reflection.registerCrcToTypeAlias(0x0B61E593, #typeof(FormLine))
    Reflection.registerCrcToTypeAlias(0xAA87EC6A, #typeof(FormDraw))
    Reflection.registerCrcToTypeAlias(0xE0321F5E, #typeof(FormShape))
    Reflection.registerCrcToTypeAlias(0xE1FEF6A2, #typeof(FormText))
    Reflection.registerCrcToTypeAlias(0xE5350EB8, #typeof(FormArrow))
    Reflection.registerCrcToTypeAlias(0xF83FE4D9, #typeof(FormImage))
}

#main
{
    let args = Env.getArgs()
    for arg in args
    {
        if !Path.isValidPathName(arg) do
            continue
        if !Image.canLoad(arg) do
            continue
        Clipboard.addString(arg)
        if Surface.sendCustomMessage("Captme", 1, 0) do
            return
    }

    try Jobs.setNumWorkers()
    try Library.init()

    let path = Path.combine(Library.getFolder(), "captme.cfg")
    g_App.setConfigPath(path)

    var img = assume Image.decode(".png", Icons48)
    img.crop(48, 48, 48, 48)
    img.setPixelFormat(.BGRA8)
    g_App.setAppIcon(img)

    let surface = try g_App.createSurface(0, 0, 10, 10, SurfaceFlags.OverlappedWindow, surfaceID: "Captme")
    let mainWnd = MainWnd.create(surface.wnd)

    if Env.hasArg("swag.test") do
        g_App.maxRunFrame = 50
    if !Env.hasArg("--hide") do
        surface.show()

    // Show the app icon in the notification area (system tray). Right-clicking it
    // is delivered to MainWnd.onSysUserEvent as a WM_USER event; the icon is removed
    // automatically when the surface is destroyed.
    surface.setTrayIcon(img, "Captme")

    with Env
    {
        .registerApplication("Captme", "Captme")
        .associateFileExtension(".png", "Captme", Env.getExe())
        .associateFileExtension(".jpg", "Captme", Env.getExe())
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
