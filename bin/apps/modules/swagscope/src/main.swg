#global using Core, Pixel, Gui

const AppIcon = #include("../datas/appicon.png")

var g_App: Application

const ProductName   = "Swag Scope"
const ApplicationId = "swagscope"
const SurfaceId     = "swag.scope"

// Selects a path without touching its drive; classification happens after the first frame.
func viewerStartupFiles(arguments: const [..] string)->Array'String
{
    var result: #returntype
    if arguments.count <= 1 do
        return result

    for argument in arguments[1 to]
    {
        let runtimeSetting = argument == "swag.sandbox" or argument == "swag.test" or Utf8.startsWith(argument, "swag.") and Utf8.contains(argument, "=")
        if not runtimeSetting and not Utf8.startsWith(argument, "--") and Path.isValidPathName(argument) do
            result.add(String.from(argument))
    }

    return result
}

// Selects the first path for callers that review a single file.
func viewerStartupFile(arguments: const [..] string)->String
{
    let files = viewerStartupFiles(arguments)
    return files.isEmpty() ? String{} : files[0]
}

// Runs the viewer review over the fixture directory it names: `--review-viewers=<directory>`.
const ViewerSmokeArgument = "--review-viewers="

// Returns the fixture directory named by the smoke-review argument, or an empty string.
func viewerSmokeDirectory(arguments: const [..] string)->String
{
    if arguments.count <= 1 do
        return {}

    for argument in arguments[1 to] where Utf8.startsWith(argument, ViewerSmokeArgument) do
        return argument[ViewerSmokeArgument.count to]
    return {}
}

private func registerViewerFileTypes(registry: const *ViewerPluginRegistry)
{
    Env.registerApplication(ApplicationId, ProductName)
    for plugin in registry.plugins where plugin.matchNames
    {
        for extension in plugin.selectors where extension[] != "*" and extension[].toString()[0] == '.' do
            Env.associateFileExtension(extension[], ApplicationId, Env.executablePath())
    }
}

#main
{
    var index = createViewerPluginRegistry()

    // Installers opt into registry work once. Normal viewing never pays for dozens of file-type
    // registrations, which keeps both cold and warm launches on the shortest path.
    if Env.hasArgument("--register-file-types")
    {
        registerViewerFileTypes(&index)
        return
    }

    // Large image, audio, and video viewers fan their independent work through the runtime's
    // shared worker pool. Starting it here keeps that cost out of the first opened file.

    g_App.setAppIcon(expect Image.decode(".png", AppIcon))
    g_App.setStatePath(Path.combine(Env.getSpecialDirectory(.UserAppData), "Swag", "scope", "settings.scc"))
    registerAppStrings(&g_App.resources)

    let surface = try g_App.createSurface(80, 50, ViewerWindow.MinWidth, 680, SurfaceFlags.StandardWindow, surfaceId: SurfaceId)
    g_App.theme.setDark()
    g_App.notifyThemeChanged()
    surface.setTitle(ProductName)

    let workspace = ViewerWorkspace.create(surface.wnd, #move index)
    let window    = workspace.primary
    window.home.useSystemPlaces = true
    window.home.refresh()

    // The file is queued before the window shows, so the first frame is the surface that
    // file is about to fill rather than the hint to drop one.
    let smokeDirectory = viewerSmokeDirectory(Env.arguments())
    if not smokeDirectory.isEmpty()
    {
        // The review owns termination after the last fixture. A compiler smoke frame bound would
        // otherwise be allowed to report success before a progressive viewer had finished.
        g_App.maxRunFrame = Swag.U32.Max
        window.reviewSmokeFixtures(smokeDirectory)
    }
    else
    {
        workspace.startupFiles = viewerStartupFiles(Env.arguments())
        let count = workspace.startupFiles.count
        workspace.startupLayout = Env.hasArgument("--grid") ? sceneGrid(count) :
                                  (count == 2 ? SceneLayout.SideBySide : SceneLayout.Auto)
    }

    surface.show()

    let exitCode = g_App.run()
    if exitCode do
        Env.exit(exitCode)
}
