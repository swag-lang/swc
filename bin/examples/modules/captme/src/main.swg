var g_App: Application

const NotifyIconVersion4 = 4

#premain
{
    discard Memory.installFastAllocator(electricMode: #hastag("CaptMe.ElectricMemory"), detectLeaks: true, captureStack: false, trackAllocations: #hastag("CaptMe.TrackMemory"))

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
    foreach arg in args
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
        g_App.maxRunFrame = 100
    if !Env.hasArg("--hide") do
        surface.show()

    // Icon task bar
    with Win32
    {
        let hIcon = catch img.toHICON()
        defer catch DestroyIcon(hIcon)

        with var tnid: NOTIFYICONDATAA
        {
            .cbSize           = #sizeof(NOTIFYICONDATAA)
            .hWnd             = surface.hWnd
            .uID              = 1
            .uFlags           = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP
            .uCallbackMessage = WM_USER
            .hIcon            = hIcon
            Memory.copy(&.szTip[0], @dataof("Captme"), @countof("Captme"))
        }

        catch Shell_NotifyIconA(NIM_ADD, &tnid)
        tnid.uVersion = NotifyIconVersion4
        catch Shell_NotifyIconA(NIM_SETVERSION, &tnid)
        defer catch Shell_NotifyIconA(NIM_DELETE, &tnid)
    }

    with Env
    {
        .registerApplication("Captme", "Captme")
        .associateFileExtension(".png", "Captme", Env.getExe())
        .associateFileExtension(".jpg", "Captme", Env.getExe())
    }

    foreach arg in args
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
