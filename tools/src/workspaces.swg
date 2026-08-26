#global namespace Tool

using Core

/*
The five source workspaces, and the commands that reach into them.

`test` runs a module's `#test` functions and never its `#main`; `smoke` runs the real program for
a bounded number of frames, isolated from the machine, to prove it starts and keeps going. A
program without `#test` is smoked: testing it would report zero tests and prove nothing.
*/
public func runStd(context: *Context, options: *Options)->s32 fail
{
    var arguments: Arguments
    arguments.add(["build", "--workspace", context.workspacePath("std").toString(), "--build-cfg", options.buildCfg.toString()])
    if !options.module.isEmpty() do
        arguments.add(["--workspace-module", options.module.toString()])

    options.appendExtra(&arguments)

    let built = try context.runCompiler(arguments)
    if built != 0 do
        return built
    if options.command != "test" do
        return 0

    // A module is tested from its own module file, against the API the workspace build published.
    for name in context.workspaceModules("std")
    {
        if !options.module.isEmpty() and options.module != name[] do
            continue

        let moduleDir = Path.combine(context.workspacePath("std").toString(), "modules", name.toString())
        if !hasUnitTests(moduleDir.toString()) do
            continue

        let code = try testStdModule(context, options, name.toString(), moduleDir.toString())
        if code != 0 do
            return code
    }

    return 0
}

// Reports whether a standard library module declares unit tests of its own.
//
// Every module keeps them in `src/tests`, so one look answers the question.
private func hasUnitTests(moduleDir: string)->bool
{
    return holdsTestSource(Path.combine(moduleDir, "src", "tests").toString())
}

private func holdsTestSource(directory: string)->bool
{
    let entries = catch Directory.enumerateFiles(directory, ".swg", recurse: true) as err
    if err != null do
        return false

    for entry in entries
    {
        let name = Path.fileName(entry.fullname.toString()) orelse ""
        if Utf8.endsWith(cast(const [..] u8) name, ".test.swg") do
            return true
    }

    return false
}

private func testStdModule(context: *Context, options: *Options, name: string, moduleDir: string)->s32 fail
{
    let paths = context.artifactPaths(Format.toString("std/%", name).toString(), "executable", options.buildCfg.toString())

    var arguments: Arguments
    arguments.add(["test", "--artifact-kind", "executable"])
    arguments.add(["--module-file", Path.combine(moduleDir, "module.swg").toString(), "-d", "src"])
    arguments.add(["--out-dir", paths.outDir.toString(), "--work-dir", paths.workDir.toString()])
    arguments.add(["--build-cfg", options.buildCfg.toString()])
    arguments.add(["--import-api-dir", context.workspaceOutput("std").toString()])

    // Native execution covers the library contract in every configuration. Release also keeps
    // the JIT pass as a cross-backend check where inlining is most aggressive.
    if options.buildCfg != "release" do
        arguments.add(["--no-test-jit"])

    options.appendTest(&arguments)
    options.appendExtra(&arguments)
    options.appendRunArguments(&arguments)
    return try context.runCompiler(arguments)
}

// Builds, runs, tests, or smokes the examples workspace, whole or one module.
public func runExamples(context: *Context, options: *Options)->s32 fail
{
    var command = options.command
    if command.isEmpty() do
        command = String.from("build")

    var arguments: Arguments
    arguments.add([command.toString(), "--workspace", context.workspacePath("examples").toString()])
    arguments.add(["--build-cfg", options.buildCfg.toString()])
    if !options.module.isEmpty() do
        arguments.add(["--workspace-module", options.module.toString()])

    options.appendWorkspace(&arguments)
    options.appendRunArguments(&arguments)
    if command == "test" do
        options.appendTest(&arguments)
    options.appendExtra(&arguments)
    return try context.runCompiler(arguments)
}

// Builds, runs, tests, or smokes one or every module in the applications workspace.
//
// Each application asks for its dependencies beside its executable through
// `publishDependencies` in its own module file, so every command leaves it launchable.
public func runApps(context: *Context, options: *Options)->s32 fail
{
    var command = options.command
    if command.isEmpty() do
        command = String.from("build")

    if command == "run" and options.module.isEmpty()
    {
        Console.println("Running an application needs its name: swc tools/apps.swgs run <module>")
        return 1
    }

    if command == "run" do
        return try launchApplication(context, options)

    return try runApplicationWorkspace(context, options, options.module.toString(), command.toString())
}

// Runs one command over the applications workspace, optionally selecting one application module.
private func runApplicationWorkspace(context: *Context, options: *Options, name, command: string)->s32 fail
{
    var arguments: Arguments
    arguments.add([command, "--workspace", applicationWorkspace(context).toString()])
    arguments.add(["--build-cfg", options.buildCfg.toString()])
    if @countof(name) do
        arguments.add(["--workspace-module", name])

    // Applications and test-enabled library modules run once in their emitted artifacts. An
    // explicit --test-jit can still opt back into the in-process pass.
    if command == "test" do
        arguments.add(["--no-test-jit"])

    if command != "build"
    {
        options.appendWorkspace(&arguments)
        options.appendRunArguments(&arguments)

        // sFileScope's smoke is a format review, not only a startup check: the application opens
        // the immutable fixture attached to every registered viewer and exits when all are ready.
        if command == "smoke" and name == "sFileScope" and !options.hasRunArgument("--review-viewers")
        {
            let fixtures = Path.combine(applicationWorkspace(context).toString(), "modules", "sFileScope", "src", "tests", "datas")
            arguments.add(["--run-arg", Format.toString("--review-viewers=%", fixtures).toString()])
        }
    }

    if command == "test" do
        options.appendTest(&arguments)

    options.appendExtra(&arguments)

    let code = try context.runCompiler(arguments)
    if code != 0 or command != "build" do
        return code

    if @countof(name) do
        return try packageApplication(context, options, name)
    for moduleName in context.workspaceModules("apps")
    {
        let packaged = try packageApplication(context, options, moduleName.toString())
        if packaged != 0 do
            return packaged
    }

    return 0
}

// Launches the packaged executable from its own directory, so it finds the files beside it.
private func launchApplication(context: *Context, options: *Options)->s32 fail
{
    let built = try runApplicationWorkspace(context, options, options.module.toString(), "build")
    if built != 0 do
        return built

    let directory  = applicationDirectory(context, options, options.module.toString())
    let executable = Path.combine(directory.toString(), Format.toString("%.exe", options.module.toString()).toString())

    let applicationArguments = joinArguments(options.runArguments.toSlice())

    var info    = Env.StartInfo{fileName: executable.toString(), arguments: applicationArguments.toString(), workingDirectory: directory.toString(), environment: &context.childEnv}
    var process = try Env.startProcess(info)
    if options.runAsync
    {
        Console.println("Started ", options.module.toString(), " (process ", process.processId, ").")
        return 0
    }

    return try process.waitForExit()
}

private func applicationDirectory(context: *Context, options: *Options, name: string)->String
{
    return Path.combine(applicationWorkspace(context).toString(), ".output", name, "executable", options.buildCfg.toString(), context.targetArch.toString())
}

// Returns the workspace containing every standard application.
private func applicationWorkspace(context: *Context)->String
{
    return context.workspacePath("apps")
}

// Copies the runtime files one application owns beside its built executable.
//
// The standard library is not copied here: the link publishes it itself, and removes any library
// it did not publish, so a copy made here would only be deleted by the next link.
private func packageApplication(context: *Context, options: *Options, name: string)->s32 fail
{
    let appDir     = applicationDirectory(context, options, name)
    let executable = Path.combine(appDir.toString(), Format.toString("%.exe", name).toString())
    if !File.exists(executable)
    {
        Console.println("Application executable is missing: ", executable.toString())
        return 1
    }

    let moduleDir = Path.combine(applicationWorkspace(context).toString(), "modules", name)
    if name != "sVaultDrive" do
        return 0

    let vendor = Path.combine(moduleDir.toString(), "vendor", "winfsp")

    try copyBeside(Path.combine(vendor.toString(), "runtime", "winfsp-x64.dll").toString(), appDir.toString(), "winfsp-x64.dll")
    try copyBeside(Path.combine(vendor.toString(), "runtime", "winfsp-x64.sys").toString(), appDir.toString(), "winfsp-x64.sys")
    try copyBeside(Path.combine(moduleDir.toString(), "LICENCE.md").toString(), appDir.toString(), "LICENCE.md")
    try copyBeside(Path.combine(moduleDir.toString(), "THIRDPARTY.md").toString(), appDir.toString(), "THIRDPARTY.md")

    for obsoleteName in ["LICENSE.md", "THIRD-PARTY-NOTICES.md", "WinFsp-LICENSE.txt"]
    {
        let obsolete = Path.combine(appDir.toString(), obsoleteName)
        if File.exists(obsolete) do
            discard catch File.delete(obsolete.toString())
    }

    let installer = Path.combine(appDir.toString(), "winfsp-2.2.26215.msi")
    if File.exists(installer) do
        discard catch File.delete(installer.toString())

    return 0
}

private func copyBeside(source: string, directory: string, name: string) fail
{
    let target = Path.combine(directory, name)
    try File.duplicate(target.toString(), source)
}

// Builds or tests the executable language reference.
//
// Every reference page is a compiled source, so building one is testing it without running the
// samples. The command stays `test` either way; `build` only stops short of executing.
public func runReference(context: *Context, options: *Options)->s32 fail
{
    if !options.module.isEmpty()
    {
        Console.println("The language reference is one workspace and takes no module name.")
        return 1
    }

    var arguments: Arguments
    arguments.add(["test", "--workspace", context.workspacePath("reference").toString()])
    arguments.add(["--build-cfg", options.buildCfg.toString()])

    // The language suites compare JIT and native behavior; the reference checks the documented
    // programs once in their shipped native form.
    if options.command == "build" do
        arguments.add(["--no-test-jit", "--no-output"])
    else
    {
        arguments.add(["--no-test-jit"])
        options.appendTest(&arguments)
    }

    options.appendExtra(&arguments)
    return try context.runCompiler(arguments)
}

// Runs one standalone example script, or smokes every one of them.
//
// A script declares no `#test`, so there is nothing for a test command to run. What is worth
// proving is that it starts and keeps going, which is what a smoke run proves.
public func runScripts(context: *Context, options: *Options)->s32 fail
{
    let scriptsDir = Path.combine(context.workspacePath("examples").toString(), "scripts")

    var command = options.command
    if command.isEmpty()
    {
        command = String.from("smoke")
        if !options.module.isEmpty() do
            command = String.from("run")
    }

    // A name is resolved before anything is built, so a typo costs nothing.
    var named: String
    if !options.module.isEmpty()
    {
        named = Path.combine(scriptsDir.toString(), options.module.toString())
        if !Utf8.endsWith(cast(const [..] u8) named.toString(), ".swgs") do
            named += ".swgs"
        if !File.exists(named)
        {
            Console.println("Unknown script \"", options.module.toString(), "\". Available scripts:")
            for script in scriptFiles(scriptsDir.toString()) do
                Console.println("  ", Path.fileNameWithoutExtension(script.toString()) orelse "")
            return 1
        }
    }

    if !named.isEmpty() do
        return try runOneScript(context, options, command.toString(), named.toString())

    for script in scriptFiles(scriptsDir.toString())
    {
        let code = try runOneScript(context, options, command.toString(), script.toString())
        if code != 0 do
            return code
    }

    return 0
}

private func scriptFiles(scriptsDir: string)->Array'String
{
    var result: retval

    let entries = catch Directory.enumerateFiles(scriptsDir, ".swgs") as err
    if err != null do
        return result

    for entry in entries do
        result.add(entry.fullname)
    return result
}

// A script has no smoke command of its own: the run markers are what bound and isolate it.
// The bare marker takes the default frame budget, and an explicit one always wins.
private func runOneScript(context: *Context, options: *Options, command: string, script: string)->s32 fail
{
    // The compiler reads what comes before the script and hands everything after it to the
    // script itself, so the two halves are built in that order.
    var arguments: Arguments
    arguments.add(["--build-cfg", options.buildCfg.toString()])
    options.appendWorkspace(&arguments)
    options.appendExtra(&arguments)

    arguments.add([script])

    if command == "smoke"
    {
        if !options.hasRunArgument("swag.smoke") do
            arguments.add(["swag.smoke"])
        if !options.hasRunArgument("swag.sandbox") do
            arguments.add(["swag.sandbox"])
    }

    for value in options.runArguments do
        arguments.add([value.toString()])

    return try context.runCompiler(arguments)
}
