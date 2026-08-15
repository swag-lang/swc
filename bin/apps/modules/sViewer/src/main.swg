#global using Core, Pixel, Gui

const AppIcon            = #include("../datas/appicon.png")
const DefaultPluginIndex = #include("../datas/plugins/index.viewer")

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

private func registerViewerFileTypes(index: const *ViewerPluginIndex)
{
    with Env
    {
        .registerApplication("sViewer", "sViewer")
        for spec in index.specs
        {
            for extension in spec.extensions where extension[] != "*" do
                .associateFileExtension(extension[].toString(), "sViewer", Env.executablePath())
        }
    }
}

#main
{
    let pluginDirectory = Path.combine(Path.directoryName(Env.executablePath()) orelse ".", "plugins")
    let pluginIndexFile = Path.combine(pluginDirectory, "index.viewer")
    let index           = File.exists(pluginIndexFile) ? try ViewerPluginIndex.load(pluginIndexFile) : try ViewerPluginIndex.parse(cast(string) DefaultPluginIndex, pluginDirectory)

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

    let surface = (try g_App.createSurface(80, 50, 960, 680, SurfaceFlags.StandardWindow, surfaceId: "sViewer"))!
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
