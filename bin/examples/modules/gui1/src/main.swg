using Core, Gui

const TestFrames = 50

var app:      Application
var g_Button: #null *PushButton

func centerButton(view: *Wnd)
{
    let button = g_Button
    if !button do
        return

    let clientRect = view.clientRect()
    let x          = clientRect.horzCenter() - button.position.width * 0.5
    let y          = clientRect.vertCenter() - button.position.height * 0.5
    button.setPosition({x, y, button.position.width, button.position.height})
}

func onEvent(view: *Wnd, evt: IEvent)->bool
{
    switch evt
    {
    case ResizeEvent: centerButton(view)
    }

    return false
}

#main
{
    let surface = notnull (try app.createSurface(100, 100, 594, 449, SurfaceFlags.StandardWindow))
    surface.setTitle("GUI example")

    let view = surface.view()
    view.hookOnEvent = &onEvent
    g_Button         = PushButton.create(view, "Push Button")
    centerButton(view)

    if Env.isSmokeRun() do
        app.maxRunFrame = TestFrames

    surface.show()

    app.run()
}
