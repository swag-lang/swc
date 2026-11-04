#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

func registrationPeer() fail
{
    let root = Env.variable("SWAG_REGISTRATION_ROOT")
    Swag.require(not root.isEmpty() and Directory.exists(root) and not Env.isSandboxed())
    Swag.require(Env.variable("XDG_DATA_HOME") == Path.combine(root, "data"))
    Swag.require(Env.variable("XDG_CONFIG_HOME") == Path.combine(root, "config"))
    let applications = Path.combine(root, "data", "applications")
    let desktop      = Path.combine(applications, "swag-xdg-test.desktop")
    Env.registerApplication("swag-xdg-test", "Swag XDG Test")
    Swag.require(File.exists(desktop))

    let baseline = Env.claimFileExtension(".txt", "swag-xdg-baseline", "Plain text", "/bin/true")
    Swag.require(baseline)
    let associated = Env.associateFileExtension(".txt", "swag-xdg-test", Env.executablePath())
    Swag.require(associated)
    let query = try Env.runProcess("gio", ["mime", "text/plain"])
    Swag.require(query.exitCode() == 0)
    let output = String.from(query.standardOutput())
    for line in Tokenize.splitLines(output.toString())
    {
        Swag.require(Utf8.contains(line, "swag-xdg-baseline.desktop"))
        break
    }

    let custom = Env.associateFileExtension(".swagxdgtest", "swag-xdg-test", Env.executablePath())
    Swag.require(custom)
    let claimed = Env.claimFileExtension(".swagxdgtest", "swag-xdg-test", "Swag & <document>", Env.executablePath())
    Swag.require(claimed)
    let definition = try File.readAllText(Path.combine(root, "data/mime/packages/swag-extension-swagxdgtest.xml"))
    Swag.require(definition.contains("Swag &amp; &lt;document&gt;"))
    let entry = try File.readAllText(desktop)
    Swag.require(entry.contains("Name=Swag XDG Test"))

    // GIO must launch an executable with literal shell and desktop field-code characters.
    let executable = Path.combine(root, "viewer $literal `quoted` \"name\" %.sh")
    discard try File.writeAllText(executable, "#!/bin/sh\nprintf '%s' \"$1\" > \"$SWAG_REGISTRATION_OPENED\"\n")
    let permissions = try Env.runProcess("chmod", ["+x", executable.toString()])
    Swag.require(permissions.exitCode() == 0)
    let quoted = Env.associateFileExtension(".txt", "swag-xdg-quoted", executable)
    Swag.require(quoted)
    let document = Path.combine(root, "document space café.txt")
    discard try File.writeAllText(document, "example")
    let marker      = Path.combine(root, "opened")
    var environment = Env.currentEnvironment()
    environment.set("SWAG_REGISTRATION_OPENED", marker)
    let quotedDesktop = Path.combine(applications, "swag-xdg-quoted.desktop")
    let arguments     = ["launch", quotedDesktop.toString(), document.toString()]
    let launched      = try Env.runProcess(Env.StartInfo{fileName: "gio", arguments: arguments, environment: &environment,
                                                         standardOutput: .Pipe, standardError: .Pipe})
    Swag.require(launched.exitCode() == 0, String.from(launched.standardError()).toString())
    for 200 where not File.exists(marker) do
        Threading.Thread.sleep(Time.Duration.fromMilliseconds(10))
    let opened = try File.readAllText(marker)
    Swag.require(opened == document)

    let before = try File.readAllText(Path.combine(root, "config/mimeapps.list"))
    Swag.require(not Env.associateFileExtension(".txt", "../escape", "/bin/true"))
    Swag.require(not Env.associateFileExtension("../txt", "swag-xdg-test", "/bin/true"))
    Swag.require(not Env.associateFileExtension(".txt", "swag-xdg-test", "relative"))
    let after = try File.readAllText(Path.combine(root, "config/mimeapps.list"))
    Swag.require(before == after)

    try Env.enterSandbox(Path.combine(root, "sandbox"))
    let denied = Env.deniedSystemMutations()
    Env.registerApplication("swag-xdg-denied", "Denied")
    let offered = Env.associateFileExtension(".txt", "swag-xdg-denied", "/bin/true")
    let taken   = Env.claimFileExtension(".txt", "swag-xdg-denied", "Denied", "/bin/true")
    Swag.require(not offered and not taken and Env.deniedSystemMutations() == denied + 3)
    Swag.require(not File.exists(Path.combine(applications, "swag-xdg-denied.desktop")))
}

#premain
{
    if Env.hasArgument("--swag-registration-peer")
    {
        if Env.hasArgument("unavailable") or Env.hasArgument("config-file")
        {
            let root = Env.variable("SWAG_REGISTRATION_ROOT")
            Swag.require(not root.isEmpty() and Directory.exists(root) and not Env.isSandboxed())
            let offered = Env.associateFileExtension(".txt", "swag-xdg-test", "/bin/true")
            let claimed = Env.claimFileExtension(".txt", "swag-xdg-test", "Test", "/bin/true")
            Swag.require(not offered and not claimed)
            if Env.hasArgument("unavailable")
            {
                Env.registerApplication("swag-xdg-test", "Test")
                Swag.require(not Directory.exists(Path.combine(root, "data/applications")))
            }
            else
            {
                let retained = expect File.readAllText(Path.combine(root, "config"))
                Swag.require(retained == "keep")
            }
        }
        else
        {
            expect registrationPeer()
        }

        Env.exit(0)
    }
}

// Native only: the isolated peer is this test executable, not the compiler hosting a JIT test.
#[Swag.TestTag("integration.desktop.registration")]
#test
{
    Swag.require(not Swag.jit(), "run desktop registration integration with --no-test-jit")
    for mode in ["normal", "unavailable", "config-file"]
    {
        let root = CoreTests.makeFilesystemTestPath(Format.toString("xdg-registration-%", mode))
        expect Directory.create(root, recurse: true)
        defer expect Directory.delete(root, recurse: true)
        var environment = Env.currentEnvironment()
        environment.set("SWAG_REGISTRATION_ROOT", root)
        environment.set("XDG_DATA_HOME", Path.combine(root, "data"))
        environment.set("XDG_CONFIG_HOME", Path.combine(root, "config"))
        environment.set("XDG_CACHE_HOME", Path.combine(root, "cache"))
        environment.set("LC_ALL", "C")
        if mode == "unavailable"
        {
            let libraries = Path.combine(root, "native")
            expect Directory.create(libraries)
            discard expect File.writeAllText(Path.combine(libraries, "libgio-2.0.so.0"), "not an ELF library")
            environment.set("LD_LIBRARY_PATH", Format.toString("%:%", libraries, Env.variable("LD_LIBRARY_PATH")))
        }
        elif mode == "config-file"
        {
            discard expect File.writeAllText(Path.combine(root, "config"), "keep")
        }

        let arguments  = ["--swag-registration-peer", mode]
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

        let completed = expect process.tryWaitForExit(Time.Duration.fromSeconds(15))
        Swag.require(completed)
        if process.exitCode() != 0
        {
            Console.print(String.from(process.standardOutput()))
            Console.print(String.from(process.standardError()))
        }

        Swag.require(process.exitCode() == 0)
    }
}
