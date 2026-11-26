// Gives standalone demos a caption above the drawing area.
using Gui

func runExample(width, height: s32, title: string, hook: HookEvent, canSize = true, init: (func(*Application))? = null) fail
{
    var app: Application
    var flags = SurfaceFlags.SmallCaption | .MinimizeButton | .CloseButton | .Border
    if canSize do
        flags |= .Resizable | .MaximizeButton

    let metrics       = ThemeMetrics{}
    let captionHeight = cast(s32, metrics.wnd_SmallCaptionCY)
    let surface       = try app.createSurface(100, 100, width, height + captionHeight, flags, hook: hook)
    surface.setTitle(title)
    if init do
        init(&app)
    surface.show()
    app.run()
}
