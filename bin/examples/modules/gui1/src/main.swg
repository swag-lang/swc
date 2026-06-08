using Core, Gui

const TestFrames = 100

var app: Application

#main
{
    let surface = try app.createSurface(100, 100, 640, 480, SurfaceFlags.OverlappedWindow)
    surface.setTitle("GUI example")

    if Env.hasArg("swag.test") do
        app.maxRunFrame = TestFrames

    surface.show()

    app.run()
}
