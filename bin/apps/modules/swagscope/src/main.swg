#global using Core, Pixel, Gui

const AppIcon             = #include("../datas/appicon.png")
const ViewerSmokeArgument = "--review-viewers="

var g_App: Application

const ProductName   = "Swag Scope"
const ApplicationId = "swagscope"
const SurfaceId     = "swag.scope"

func viewerStartupFile(arguments: const [..] string)->String
{
    if arguments.count <= 1 do
        return {}

    for argument in arguments[1 until arguments.count]
    {
        if Path.isValidPathName(argument) and File.exists(argument) do
            return String.from(argument)
    }

    return {}
}

func viewerSmokeDirectory(arguments: const [..] string)->String
{
    if arguments.count <= 1 do
        return {}

    for argument in arguments[1 until arguments.count]
    {
        if !Utf8.startsWith(cast(const [..] u8) argument, ViewerSmokeArgument) do
            continue
        return String.from(argument[ViewerSmokeArgument.count until argument.count])
    }

    return {}
}

private func registerViewerFileTypes(registry: const *ViewerPluginRegistry)
{
    with Env
    {
        .registerApplication(ApplicationId, ProductName)
        for plugin in registry.plugins where plugin.matchNames
        {
            for extension in plugin.selectors where extension[] != "*" and extension[].toString()[0] == '.' do
                .associateFileExtension(extension[].toString(), ApplicationId, Env.executablePath())
        }
    }
}

#main
{
    let index = createViewerPluginRegistry()

    // Installers opt into registry work once. Normal viewing never pays for dozens of file-type
    // registrations, which keeps both cold and warm launches on the shortest path.
    if Env.hasArgument("--register-file-types")
    {
        registerViewerFileTypes(&index)
        return
    }

    // Large image, audio, and video viewers fan their independent work through the shared
    // scheduler. Without workers those paths silently execute on the GUI thread in serial.
    try Jobs.initialize()

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
    registerMidiStrings(&g_App)
    registerPdfStrings(&g_App)
    registerSoundStrings(&g_App)
    registerSubtitleStrings(&g_App)
    registerTableStrings(&g_App)
    registerVideoStrings(&g_App)

    let stateRoot = Path.combine(Env.getSpecialDirectory(.UserAppData), "Swag")
    if !Directory.exists(stateRoot) do
        discard catch Directory.create(stateRoot)
    let stateFolder = Path.combine(stateRoot, "scope")
    if !Directory.exists(stateFolder) do
        discard catch Directory.create(stateFolder)
    if Directory.exists(stateFolder)
    {
        g_App.setStatePath(Path.combine(stateFolder, "settings.scc"))
    }

    let surface = (try g_App.createSurface(80, 50, ViewerMinWidth, 680, SurfaceFlags.StandardWindow, surfaceId: SurfaceId))!
    g_App.theme.setSwagDark()
    g_App.notifyThemeChanged()
    surface.setTitle(appStrings().ui_WindowTitle)

    let window = ViewerWindow.create(surface.wnd, #move index)

    // The file is queued before the window shows, so the first frame is the surface that
    // file is about to fill rather than the hint to drop one.
    let smokeDirectory = viewerSmokeDirectory(Env.arguments())
    if !smokeDirectory.isEmpty()
    {
        // The review owns termination after the last fixture. A compiler smoke frame bound would
        // otherwise be allowed to report success before a progressive viewer had finished.
        g_App.maxRunFrame = Swag.U32.Max
        window.reviewSmokeFixtures(smokeDirectory.toString())
    }
    else
    {
        let startupFile = viewerStartupFile(Env.arguments())
        if !startupFile.isEmpty() do
            window.queueFile(startupFile.toString())
    }

    surface.show()

    let exitCode = g_App.run()
    if exitCode do
        Env.exit(exitCode)
}
