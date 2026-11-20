#global using Core, Pixel, Gui, Screen

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
    // The first image named on the command line opens in the editor, in the running instance
    // when there is one.
    var imageToOpen: string = ""
    for arg in Env.arguments() where Path.isValidPathName(arg) and Image.canLoad(arg)
    {
        imageToOpen = arg
        break
    }

    if imageToOpen.count
    {
        Clipboard.addString(imageToOpen)
        if Surface.sendCustomMessage(SurfaceId, OpenImageMessage, 0) do
            return
    }

    try Library.init()

    // Settings use a role-based file name so a product rename does not change their identity.
    g_App.setStatePath(Library.getStatePath())

    let appIcon = expect Image.decode(".png", AppIcon)
    g_App.setAppIcon(appIcon)
    registerAppStrings(&g_App.resources)

    let surface = try g_App.createSurface(0, 0, 10, 10, SurfaceFlags.StandardWindow, surfaceId: SurfaceId)
    g_App.theme.setDark()
    g_App.notifyThemeChanged()
    let mainWnd = MainWnd.create(surface.wnd)

    // An explicit file opens the editor. A normal launch opens the capture workspace.
    mainWnd.restoreState()

    Env.registerApplication(ApplicationId, ProductName)
    Env.associateFileExtension(".png", ApplicationId, Env.executablePath())
    Env.associateFileExtension(".jpg", ApplicationId, Env.executablePath())

    if imageToOpen.count
    {
        mainWnd.showWindow()
        mainWnd.loadExternalImage(imageToOpen)
    }
    else
    {
        mainWnd.postCommandEvent(ActionGlobal.ShowHub)
    }

    g_App.run()
}
