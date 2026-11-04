#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

func chooserControl(method: string, version: string = "", mode: string = "")->String fail
{
    let qualified = Format.toString("org.swag.TestPortal.%", method)
    var command: Array'string
    for argument in ["call", "--session", "--dest", "org.swag.TestPortal", "--object-path",
                     "/org/freedesktop/portal/desktop", "--method"] do
        command.add(argument)
    command.add(qualified.toString())
    for argument in [version, mode] where argument != "" do
        command.add(argument)
    let result = try Env.runProcess("gdbus", command.toSlice())
    Swag.require(result.exitCode() == 0, String.from(result.standardError()).toString())
    return String.from(result.standardOutput())
}

func desktopChooserPeer() fail
{
    let root = Env.variable("SWAG_CHOOSER_ROOT")
    Swag.require(not root.isEmpty() and Directory.exists(root) and not Env.isSandboxed())
    Swag.require(Env.variable("SWAG_CHOOSER_PRIVATE_BUS") == Env.variable("DBUS_SESSION_BUS_ADDRESS"))
    let document = Path.combine(root, "document café 'quoted' $literal %.txt")
    discard try File.writeAllText(document, "chooser UTF-8 café")
    if Env.hasArgument("unavailable") or Env.hasArgument("no-bus")
    {
        let unavailable = Env.openFileWith(document)
        Swag.require(not unavailable)
        return
    }

    discard try chooserControl("Reset", "3", "accept")
    let acceptedRequest = Env.openFileWith(document)
    Swag.require(acceptedRequest)
    let accepted = try chooserControl("Stats")
    Swag.require(accepted.contains("uint32 1, true, true, 'chooser UTF-8 café'"), accepted.toString())
    discard try chooserControl("Complete")

    // Pending requests must survive the return from openFileWith.
    for 8
    {
        let repeatedRequest = Env.openFileWith(document)
        Swag.require(repeatedRequest)
        discard try chooserControl("Complete")
    }

    let repeated = try chooserControl("Stats")
    Swag.require(repeated.contains("uint32 9, true, true,"), repeated.toString())

    discard try chooserControl("Reset", "2", "accept")
    let oldRequest = Env.openFileWith(document)
    Swag.require(not oldRequest)
    let oldPortal = try chooserControl("Stats")
    Swag.require(oldPortal.contains("uint32 0, false, false,"), oldPortal.toString())

    discard try chooserControl("Reset", "3", "reject")
    let rejectedRequest = Env.openFileWith(document)
    Swag.require(not rejectedRequest)
    discard try chooserControl("Reset", "3", "timeout")
    var clock: Time.Stopwatch
    clock.start()
    let timedOut = Env.openFileWith(document)
    Swag.require(not timedOut and clock.elapsedMilliseconds() >= 1500 and clock.elapsedMilliseconds() < 5000)
    discard try chooserControl("Reset", "3", "accept")
    let recoveredRequest = Env.openFileWith(document)
    Swag.require(recoveredRequest)
    discard try chooserControl("Complete")

    let directoryRequest = Env.openFileWith(root)
    Swag.require(directoryRequest)
    let directoryReply = try chooserControl("Stats")
    Swag.require(directoryReply.contains("true, true, '<directory>'"), directoryReply.toString())
    discard try chooserControl("Complete")

    let emptyPath = Env.openFileWith("")
    Swag.require(not emptyPath)
    let nulPath = Env.openFileWith("invalid\0path")
    Swag.require(not nulPath)
    let missingPath = Env.openFileWith(Path.combine(root, "missing"))
    Swag.require(not missingPath)
    let specialFile = Env.openFileWith("/dev/null")
    Swag.require(not specialFile)
    try Env.enterSandbox(Path.combine(root, "sandbox"))
    let sandboxedRequest = Env.openFileWith(document)
    Swag.require(not sandboxedRequest)
}

#premain
{
    if Env.hasArgument("--swag-chooser-peer")
    {
        expect desktopChooserPeer()
        Env.exit(0)
    }
}

// Explicit private bus and peer required; never contacts the user's desktop service.
// Native only: the child executable intentionally runs outside the test sandbox.
#[Swag.TestTag("integration.desktop.chooser")]
#test
{
    Swag.require(not Swag.jit(), "run desktop chooser integration with --no-test-jit")
    let address = Env.variable("SWAG_CHOOSER_PRIVATE_BUS")
    Swag.require(not address.isEmpty() and address == Env.variable("DBUS_SESSION_BUS_ADDRESS"))
    for mode in ["normal", "unavailable", "no-bus"]
    {
        let root = CoreTests.makeFilesystemTestPath(Format.toString("desktop-chooser-%", mode))
        expect Directory.create(root, recurse: true)
        defer expect Directory.delete(root, recurse: true)
        var environment = Env.currentEnvironment()
        environment.set("SWAG_CHOOSER_ROOT", root)
        if mode == "unavailable"
        {
            let libraries = Path.combine(root, "native")
            expect Directory.create(libraries)
            discard expect File.writeAllText(Path.combine(libraries, "libsystemd.so.0"), "not an ELF library")
            environment.set("LD_LIBRARY_PATH", Format.toString("%:%", libraries, Env.variable("LD_LIBRARY_PATH")))
        }
        elif mode == "no-bus"
        {
            let unavailable = Format.toString("unix:path=%/missing-bus", root)
            environment.set("DBUS_SESSION_BUS_ADDRESS", unavailable)
            environment.set("SWAG_CHOOSER_PRIVATE_BUS", unavailable)
        }

        let arguments  = ["--swag-chooser-peer", mode]
        let executable = Env.executablePath()
        with let info  = Env.StartInfo{fileName: executable, arguments: arguments, environment: &environment}
        {
            .standardOutput = .Pipe
            .standardError  = .Pipe
        }

        var process = expect Env.startProcess(info)
        defer
        {
            if process.isRunning() do
                discard catch process.kill()
        }

        let completed = expect process.tryWaitForExit(Time.Duration.fromSeconds(20))
        Swag.require(completed)
        if process.exitCode() != 0
        {
            Console.print(String.from(process.standardOutput()))
            Console.print(String.from(process.standardError()))
        }

        Swag.require(process.exitCode() == 0)
    }
}
