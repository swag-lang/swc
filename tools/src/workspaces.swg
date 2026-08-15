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

    options.appendWorkspace(&arguments)
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
private func hasUnitTests(moduleDir: string)->bool
{
    if holdsTestSource(Path.combine(moduleDir, "src", "unittests").toString()) do
        return true
    return holdsTestSource(Path.combine(moduleDir, "src", "tests", "unittests").toString())
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
    options.appendExtra(&arguments)
    return try context.runCompiler(arguments)
}

// Builds, runs, tests, or smokes the applications workspace, whole or one module.
//
// Every command publishes the standard library beside the artifact it links. That is not a
// build-only concern: a link without it *removes* the libraries a previous link published, so a
// test pass would otherwise leave the application unlaunchable.
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

    var arguments: Arguments
    arguments.add([command.toString(), "--workspace", context.workspacePath("apps").toString()])
    arguments.add(["--build-cfg", options.buildCfg.toString()])
    arguments.add(["--publish"])
    if !options.module.isEmpty() do
        arguments.add(["--workspace-module", options.module.toString()])

    // Applications are native executables; their tests run once in the emitted artifact. An
    // explicit --test-jit can still opt back into the in-process pass.
    if command == "test" do
        arguments.add(["--no-test-jit"])

    options.appendWorkspace(&arguments)
    options.appendRunArguments(&arguments)
    options.appendExtra(&arguments)

    let code = try context.runCompiler(arguments)
    if code != 0 do
        return code
    if command == "test" and (options.module.isEmpty() or options.module == "sViewer")
    {
        let moduleDir = Path.combine(context.workspacePath("apps").toString(), "modules", "sViewer")
        return try testViewerPlugins(context, options, moduleDir.toString())
    }

    if command != "build" do
        return 0

    return try packageApplications(context, options)
}

// Tests sViewer plugins as standalone executables against the just-published standard library.
// This preserves the lazy DLL boundary while making the normal application test exercise every
// shipped renderer.
private func testViewerPlugins(context: *Context, options: *Options, moduleDir: string)->s32 fail
{
    let audioCode = try buildViewerAudioRuntime(context, options)
    if audioCode != 0 do
        return audioCode

    for pluginName in ["image", "markdown", "html", "hex", "sound"]
    {
        let pluginDir = Path.combine(moduleDir, "plugins", pluginName)
        if !holdsTestSource(Path.combine(pluginDir.toString(), "src").toString()) do
            continue

        let paths = context.artifactPaths(Format.toString("apps/sViewer-plugin-%-test", pluginName).toString(), "executable", options.buildCfg.toString())
        var arguments: Arguments
        arguments.add(["test", "--artifact-kind", "executable"])
        arguments.add(["--module-file", Path.combine(pluginDir.toString(), "module.swg").toString(), "--directory", "src"])
        arguments.add(["--out-dir", paths.outDir.toString(), "--work-dir", paths.workDir.toString()])
        arguments.add(["--build-cfg", options.buildCfg.toString(), "--import-api-dir", context.workspaceOutput("std").toString()])
        arguments.add(["--no-test-jit"])
        options.appendExtra(&arguments)
        options.appendRunArguments(&arguments)

        let code = try context.runCompiler(arguments)
        if code != 0 do
            return code
    }

    return 0
}

private func packageApplications(context: *Context, options: *Options)->s32 fail
{
    for name in context.workspaceModules("apps")
    {
        if !options.module.isEmpty() and options.module != name[] do
            continue

        let code = try packageApplication(context, options, name.toString())
        if code != 0 do
            return code
    }

    return 0
}

// Launches the packaged executable from its own directory, so it finds the files beside it.
private func launchApplication(context: *Context, options: *Options)->s32 fail
{
    var arguments: Arguments
    arguments.add(["build", "--workspace", context.workspacePath("apps").toString()])
    arguments.add(["--build-cfg", options.buildCfg.toString()])
    arguments.add(["--publish"])
    arguments.add(["--workspace-module", options.module.toString()])
    options.appendExtra(&arguments)

    let built = try context.runCompiler(arguments)
    if built != 0 do
        return built

    let packaged = try packageApplication(context, options, options.module.toString())
    if packaged != 0 do
        return packaged

    let directory  = applicationDirectory(context, options, options.module.toString())
    let executable = Path.combine(directory.toString(), Format.toString("%.exe", options.module.toString()).toString())

    let applicationArguments = joinArguments(options.runArguments.toSlice())

    var info    = Env.StartInfo{fileName: executable.toString(), arguments: applicationArguments.toString(), workingDirectory: directory.toString(), environment: &context.childEnv}
    var process = try Env.startProcess(info)
    return try process.waitForExit()
}

private func applicationDirectory(context: *Context, options: *Options, name: string)->String
{
    let workspace = context.workspacePath("apps")
    return Path.combine(workspace.toString(), ".output", name, "executable", options.buildCfg.toString(), context.targetArch.toString())
}

// Copies the runtime files one application owns beside its built executable.
//
// The standard library is not copied here: the compiler publishes it itself when the tools pass
// `--publish`, and it removes any it did not publish, so a copy made here would only be deleted
// by the next link.
private func packageApplication(context: *Context, options: *Options, name: string)->s32 fail
{
    let appDir     = applicationDirectory(context, options, name)
    let executable = Path.combine(appDir.toString(), Format.toString("%.exe", name).toString())
    if !File.exists(executable)
    {
        Console.println("Application executable is missing: ", executable.toString())
        return 1
    }

    let moduleDir = Path.combine(context.workspacePath("apps").toString(), "modules", name)
    if name == "sViewer" do
        return try packageViewerPlugins(context, options, moduleDir.toString(), appDir.toString())
    if name != "sCrypt" do
        return 0

    let vendor = Path.combine(moduleDir.toString(), "vendor", "winfsp")

    try copyBeside(Path.combine(vendor.toString(), "runtime", "winfsp-x64.dll").toString(), appDir.toString(), "winfsp-x64.dll")
    try copyBeside(Path.combine(vendor.toString(), "runtime", "winfsp-x64.sys").toString(), appDir.toString(), "winfsp-x64.sys")
    try copyBeside(Path.combine(vendor.toString(), "LICENSE.txt").toString(), appDir.toString(), "WinFsp-LICENSE.txt")
    try copyBeside(Path.combine(moduleDir.toString(), "LICENSE.md").toString(), appDir.toString(), "LICENSE.md")
    try copyBeside(Path.combine(moduleDir.toString(), "THIRD-PARTY-NOTICES.md").toString(), appDir.toString(), "THIRD-PARTY-NOTICES.md")

    let installer = Path.combine(appDir.toString(), "winfsp-2.2.26215.msi")
    if File.exists(installer) do
        discard catch File.delete(installer.toString())

    return 0
}

// Builds the optional sViewer format modules beside the host without linking them into it.
//
// The host reads only `index.viewer` on startup. A DLL enters the process only after that index
// selects it for the opened extension, which keeps future plugin accumulation off the hot path.
private func packageViewerPlugins(context: *Context, options: *Options, moduleDir, appDir: string)->s32 fail
{
    let audioCode = try buildViewerAudioRuntime(context, options)
    if audioCode != 0 do
        return audioCode

    let outputDir = Path.combine(appDir, "plugins")
    if !Directory.exists(outputDir) do
        try Directory.create(outputDir)

    // This directory is a runtime payload, not a compiler output. Remove artifacts that an older
    // or interrupted local build may have left beside the loadable plugins.
    let existing = try Directory.enumerateFiles(outputDir.toString())
    for file in existing
    {
        var extension = String.from(Path.extension(file.fullname.toString()) orelse "")
        extension = extension.toLower()
        let name = Path.fileName(file.fullname.toString()) orelse ""
        if extension == ".lib" or extension == ".swgsrc" or (Utf8.startsWith(name, "sviewer_") and (extension == ".dll" or extension == ".pdb")) do
            try File.delete(file.fullname.toString())
    }

    for pluginName in ["image", "markdown", "html", "hex", "sound"]
    {
        let pluginDir = Path.combine(moduleDir, "plugins", pluginName)
        let paths     = context.artifactPaths(Format.toString("apps/sViewer-plugin-%", pluginName).toString(), "shared-library", options.buildCfg.toString())

        var arguments: Arguments
        arguments.add(["build", "--module-file", Path.combine(pluginDir.toString(), "module.swg").toString(), "--directory", "src"])
        arguments.add(["--build-cfg", options.buildCfg.toString(), "--out-dir", paths.outDir.toString(), "--work-dir", paths.workDir.toString()])
        options.appendExtra(&arguments)

        let code = try context.runCompiler(arguments)
        if code != 0 do
            return code

        let artifactName = Format.toString("sviewer_%.dll", pluginName)
        try copyBeside(Path.combine(paths.outDir.toString(), artifactName.toString()).toString(), outputDir.toString(), artifactName.toString())
        let pdbName = Format.toString("sviewer_%.pdb", pluginName)
        let pdbPath = Path.combine(paths.outDir.toString(), pdbName.toString())
        if File.exists(pdbPath) do
            try copyBeside(pdbPath.toString(), outputDir.toString(), pdbName.toString())
    }

    // The host does not import audio itself, so publishing the application cannot infer the
    // runtime needed by the lazily loaded sound plugin. Package that standard module explicitly.
    let audioPaths = context.artifactPaths("std/audio", "shared-library", options.buildCfg.toString())
    try copyBeside(Path.combine(audioPaths.outDir.toString(), "audio.dll").toString(), appDir, "audio.dll")
    let audioPdb = Path.combine(audioPaths.outDir.toString(), "audio.pdb")
    if File.exists(audioPdb) do
        try copyBeside(audioPdb.toString(), appDir, "audio.pdb")

    try copyBeside(Path.combine(moduleDir, "datas", "plugins", "index.viewer").toString(), outputDir.toString(), "index.viewer")
    return 0
}

// Builds the runtime imported only by the lazy sound plugin and publishes its API for plugin tests.
private func buildViewerAudioRuntime(context: *Context, options: *Options)->s32 fail
{
    var arguments: Arguments
    arguments.add(["build", "--workspace", context.workspacePath("std").toString()])
    arguments.add(["--workspace-module", "audio", "--build-cfg", options.buildCfg.toString()])
    options.appendWorkspace(&arguments)
    options.appendExtra(&arguments)
    return try context.runCompiler(arguments)
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
    else do
        arguments.add(["--no-test-jit"])

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
