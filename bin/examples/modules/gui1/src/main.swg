using Core, Gui

const TestFrames = 50

var app: Application
var g_Button: #null *PushButton

func centerButton(view: *Wnd)
{
    if !g_Button do
        return

    let clientRect = view.getClientRect()
    let x          = clientRect.horzCenter() - g_Button.position.width * 0.5
    let y          = clientRect.vertCenter() - g_Button.position.height * 0.5
    g_Button.setPosition({x, y, g_Button.position.width, g_Button.position.height})
}

func onEvent(view: *Wnd, evt: IEvent)->bool
{
    switch evt
    {
    case ResizeEvent:
        centerButton(view)
    }

    return false
}

#main
{
    let surface = try app.createSurface(100, 100, 594, 449, SurfaceFlags.OverlappedWindow)
    surface.setTitle("GUI example")

    let view         = surface.getView()
    view.hookOnEvent = &onEvent
    g_Button         = PushButton.create(view, "Push Button")
    centerButton(view)

    if Env.hasArg("swag.test") do
        app.maxRunFrame = TestFrames

    surface.show()

    app.run()
}
