#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

func setDesktopTestEnvironment(name: string, value: string?)
{
    let nativeName = String.from(name)
    var status: s32
    if value
    {
        let nativeValue = String.from(value)
        status = Linux.setenv(nativeName.storage(), nativeValue.storage(), 1)
    }
    else
    {
        status = Linux.unsetenv(nativeName.storage())
    }

    Swag.assert(status == 0)
}

func waitForDesktopCapture(path: string, argument: string)
{
    var clock: Time.Stopwatch
    clock.start()
    while not File.exists(path) and clock.elapsedMilliseconds() < 5000 do
        Threading.Thread.sleep(10'ms)
    let recorded = expect File.readAllText(path)
    Swag.assert(recorded == Format.toString("1\n%", argument))
    expect File.delete(path)
}

// Run in an isolated process: PATH is temporarily replaced to exercise the launch boundary.
// The helper records arguments and never starts an actual desktop application.
#[Swag.TestTag("integration.desktop.actions")]
#test
{
    var temporary = Path.combine(Env.getSpecialDirectory(.Temp), "swag-desktop-action-XXXXXX")
    let created = Linux.mkdtemp(temporary.storage())
    Swag.assert(created == temporary.buffer)
    let root = temporary.toString()
    defer expect Directory.delete(root, recurse: true)
    let launcher = Path.combine(root, "xdg-open")
    let capture  = Path.combine(root, "captured")
    let helper   = "#!/bin/sh\nprintf '%s\\n%s' \"$#\" \"$1\" > \"$SWAG_DESKTOP_CAPTURE.tmp\"\n/bin/mv \"$SWAG_DESKTOP_CAPTURE.tmp\" \"$SWAG_DESKTOP_CAPTURE\"\n"
    discard expect File.writeAllText(launcher, helper)
    let chmod = expect Env.runProcess("/bin/chmod", ["700", launcher.toString()])
    Swag.assert(chmod.exitCode() == 0)

    let original = Env.currentEnvironment()
    defer
    {
        setDesktopTestEnvironment("PATH", original.value("PATH"))
        setDesktopTestEnvironment("SWAG_DESKTOP_CAPTURE", original.value("SWAG_DESKTOP_CAPTURE"))
    }

    setDesktopTestEnvironment("PATH", root)
    setDesktopTestEnvironment("SWAG_DESKTOP_CAPTURE", capture.toString())

    for url in ["https://example.test/é?a='quote'&b=$(id);c=\\", "mailto:someone@example.test"]
    {
        let accepted = Env.openUrl(url)
        Swag.assert(accepted)
        waitForDesktopCapture(capture.toString(), url)
    }

    let relative = "-desktop: é 'quote' $(id); \\ name"
    let absolute = expect Path.absolute(relative)
    let opened   = Env.openFile(relative)
    Swag.assert(opened)
    waitForDesktopCapture(capture.toString(), absolute.toString())
    let openedAbsolute = Env.openFile(absolute.toString())
    Swag.assert(openedAbsolute)
    waitForDesktopCapture(capture.toString(), absolute.toString())

    // Executable lookup failure must be reported synchronously by both entry points.
    expect File.delete(launcher)
    let missingUrl  = Env.openUrl("https://example.test/")
    let missingFile = Env.openFile(relative)
    Swag.assert(not missingUrl and not missingFile and not File.exists(capture))
}
