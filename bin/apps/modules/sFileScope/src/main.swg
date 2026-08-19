#global using Core, Pixel, Gui

const AppIcon = #include("../datas/appicon.png")

var g_App: Application

func viewerStartupFile(arguments: const [..] string)->String
{
    if @countof(arguments) <= 1 do
        return {}

    for argument in arguments[1 until @countof(arguments)]
    {
        if Path.isValidPathName(argument) and File.exists(argument) do
            return String.from(argument)
    }

    return {}
}

private func registerViewerFileTypes(index: const *ViewerIndex)
{
    with Env
    {
        .registerApplication("sFileScope", "sFileScope")
        for spec in index.specs
        {
            for extension in spec.extensions where extension[] != "*" and extension[].toString()[0] == '.' do
                .associateFileExtension(extension[].toString(), "sFileScope", Env.executablePath())
        }
    }
}

#main
{
    let index = createViewerIndex()

    // Installers opt into registry work once. Normal viewing never pays for dozens of file-type
    // registrations, which keeps both cold and warm launches on the shortest path.
    if Env.hasArgument("--register-file-types")
    {
        registerViewerFileTypes(&index)
        return
    }

    let appIcon = expect Image.decode(".png", AppIcon)
    g_App.setAppIcon(appIcon)
    registerAppStrings(&g_App.resources)
    registerBinaryStrings(&g_App)
    registerCodeStrings(&g_App)
    registerFontStrings(&g_App)
    registerHexStrings(&g_App)
    registerHtmlStrings(&g_App)
    registerImageStrings(&g_App)
    registerMarkdownStrings(&g_App)
    registerPdfStrings(&g_App)
    registerSoundStrings(&g_App)
    registerVideoStrings(&g_App)

    let stateFolder = Path.combine(Env.getSpecialDirectory(.UserAppData), "sFileScope")
    if !Directory.exists(stateFolder) do
        discard catch Directory.create(stateFolder)
    if Directory.exists(stateFolder)
    {
        let statePath    = Path.combine(stateFolder, "sFileScope.scc")
        let previousPath = Path.combine(stateFolder, "sFileScope.cfg")
        if !File.exists(statePath) and File.exists(previousPath) do
            discard catch File.duplicate(statePath, previousPath)
        g_App.setStatePath(statePath)
    }

    let surface = (try g_App.createSurface(80, 50, ViewerMinWidth, 680, SurfaceFlags.StandardWindow, surfaceId: "sFileScope"))!
    g_App.theme.setSwagDark()
    g_App.notifyThemeChanged()
    surface.setTitle(appStrings().ui_WindowTitle)

    let window = ViewerWindow.create(surface.wnd, #move index)

    surface.show()

    let startupFile = viewerStartupFile(Env.arguments())
    if !startupFile.isEmpty() do
        window.queueFile(startupFile.toString())

    discard g_App.run()
}
