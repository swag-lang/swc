#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core, Pixel

func waitForNativeTheme(app: *Application, ack, wanted: string, light: bool)->bool
{
    let deadline = Time.monotonicMilliseconds() + 4000
    while Time.monotonicMilliseconds() < deadline
    {
        app.runFrame()
        let response = catch File.readAllText(ack) orelse String.from("")
        if response == wanted and app.usesLightTheme() == light do
            return true
    }

    return false
}

func waitForNativeMotion(app: *Application, ack, wanted: string, reduced: bool)->bool
{
    let deadline = Time.monotonicMilliseconds() + 4000
    while Time.monotonicMilliseconds() < deadline
    {
        app.runFrame()
        let response = catch File.readAllText(ack) orelse String.from("")
        if response == wanted and app.isReducedMotion() == reduced do
            return true
    }

    return false
}

// An independent XSETTINGS owner changes the actual native GUI while it remains open.
#[Swag.TestTag("integration.desktop")]
#test
{
    Swag.require(Env.variable("SWAG_TEST_ISOLATED_X11") == "1")
    var temporary = Path.combine(Env.getSpecialDirectory(.Temp), "swag-native-theme-XXXXXX")
    Swag.require(Linux.mkdtemp(temporary.storage()) == temporary.buffer)
    defer expect Directory.delete(temporary, recurse: true)
    let script = Path.combine(testSourceRoot(), "datas/xsettings.x11.peer.py")
    var peer = expect Env.startProcess(Env.StartInfo{fileName: "python3",
                                                     arguments: [script.toString(), temporary.toString()],
                                                     standardOutput: .Pipe, standardError: .Pipe})
    defer { discard catch peer.kill(); discard catch peer.waitForExit(); }
    let ready = Path.combine(temporary, "ready")
    let deadline = Time.monotonicMilliseconds() + 3000
    while not File.exists(ready) and Time.monotonicMilliseconds() < deadline do
        Threading.Thread.sleep(1'ms)
    Swag.require(File.exists(ready), peer.standardError())

    var app: Application
    app.setMotionPreference(.Reduced)
    let surface = expect app.createSurface(60, 50, 400, 300, surfaceId: "linux-native-theme")
    surface.show()
    app.refreshSystemAppearance()
    app.setAppearance(.System)
    for 8 do
        app.runFrame()
    Swag.require(app.usesLightTheme())
    var themeChanges: u32
    surface.wnd.view.hookOnEvent = func|&themeChanges|(_, event)->bool
    {
        if event is NotifyEvent as notice where notice.kind == .ThemeChanged do
            themeChanges += 1
        return false
    }

    defer surface.wnd.view.hookOnEvent = null
    let lightPixel = app.renderer.readRenderTarget(&surface.rt, 200, 150, 1, 1).pixelColor(0, 0)

    let command = Path.combine(temporary, "command")
    let ack = Path.combine(temporary, "ack")
    discard expect File.writeAllText(command, "dark")
    Swag.require(waitForNativeTheme(&app, ack.toString(), "dark", false))
    for 4 do
        app.runFrame()
    let darkPixel = app.renderer.readRenderTarget(&surface.rt, 200, 150, 1, 1).pixelColor(0, 0)
    Swag.require(lightPixel != darkPixel, "native surface did not repaint with the dark theme")
    Swag.require(themeChanges > 0, "dark theme did not emit a portable notification")
    let changesAfterDark = themeChanges

    discard expect File.writeAllText(command, "light")
    Swag.require(waitForNativeTheme(&app, ack.toString(), "light", true))
    for 4 do
        app.runFrame()
    let restoredPixel = app.renderer.readRenderTarget(&surface.rt, 200, 150, 1, 1).pixelColor(0, 0)
    Swag.require(restoredPixel == lightPixel, "native surface did not restore the light theme")
    Swag.require(themeChanges > changesAfterDark, "light theme did not emit a portable notification")

    // A live desktop motion change must finish already running decoration and allow it again
    // when animations are reenabled.
    app.setMotionPreference(.System)
    Swag.require(not app.isReducedMotion())
    var options: AnimationOptions
    options.duration = 10000'ms
    let first = app.animator.animateF32(surface.wnd.view,
                                        AnimationChannel.from("linux.native.motion.first"),
                                        0, 1, func(_, _) {}, options)
    Swag.require(app.animator.isActive(first))
    discard expect File.writeAllText(command, "reduce")
    Swag.require(waitForNativeMotion(&app, ack.toString(), "reduce", true))
    Swag.require(not app.animator.isActive(first), "running decoration survived reduced motion")

    discard expect File.writeAllText(command, "restore")
    Swag.require(waitForNativeMotion(&app, ack.toString(), "restore", false))
    let second = app.animator.animateF32(surface.wnd.view,
                                         AnimationChannel.from("linux.native.motion.second"),
                                         0, 1, func(_, _) {}, options)
    Swag.require(app.animator.isActive(second), "desktop animation preference did not recover")
    app.animator.cancel(second)
}
