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

    // History: type crcs carried by captures saved under an older hash scheme. These
    // numbers cannot be recomputed from any current name, so they stay as recorded
    // constants. A rename made today does not extend this table: it declares a
    // 'Serialization.Alias' with the old name on the renamed struct, and the registry
    // resolves it from there.
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
        if Surface.sendCustomMessage("sSnapForge", 1, 0) do
            return
    }

    try Jobs.initialize()
    try Library.init()

    // The state file stays in the default folder: it contains the configured library
    // root, so placing it inside that root would make the choice impossible to find.
    let path       = Path.combine(Library.getDefaultFolder(), "sSnapForge.scc")
    let previous   = Path.combine(Library.getDefaultFolder(), "sSnapForge.cfg")
    let legacyPath = Path.combine(Env.getSpecialDirectory(.UserDocuments), "sCapture", "sCapture.cfg")
    let fallback   = File.exists(previous) ? previous : legacyPath
    if !File.exists(path) and File.exists(fallback) do
        discard catch File.duplicate(path, fallback)
    g_App.setStatePath(path)

    let appIcon = expect Image.decode(".png", AppIcon)
    g_App.setAppIcon(appIcon)
    registerAppStrings(&g_App.resources)

    let surface = (try g_App.createSurface(0, 0, 10, 10, SurfaceFlags.StandardWindow, surfaceId: "sSnapForge"))!
    g_App.theme.setSwagDark()
    g_App.notifyThemeChanged()
    let mainWnd = MainWnd.create(surface.wnd)

    if !Env.hasArgument("--hide") do
        surface.show()

    // Show the app icon in the notification area (system tray). Portable tray actions
    // are delivered to MainWnd.onSysUserEvent; the icon is removed automatically when
    // the surface is destroyed.
    surface.setTrayIcon(appIcon, "sSnapForge")

    with Env
    {
        .registerApplication("sSnapForge", "sSnapForge")
        .associateFileExtension(".png", "sSnapForge", Env.executablePath())
        .associateFileExtension(".jpg", "sSnapForge", Env.executablePath())
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
