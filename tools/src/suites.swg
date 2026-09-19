#global namespace Tool

using Core

// The compiler test suites, in the order a campaign climbs them.
public func allSuites()->const [..] string
{
    return g_AllSuites
}

private var g_AllSuites: [9] string = ["cpp", "lexer", "parser", "sema", "jit", "safety", "sanity", "native", "workspace"]

// The suites that stop before any backend, and answer in seconds.
public func frontendSuites()->const [..] string
{
    return g_FrontendSuites
}

private var g_FrontendSuites: [4] string = ["cpp", "lexer", "parser", "sema"]

// The suites that generate code, which is where a miscompile dies.
public func codegenSuites()->const [..] string
{
    return g_CodegenSuites
}

private var g_CodegenSuites: [5] string = ["jit", "safety", "sanity", "native", "workspace"]

// Runs one named compiler suite, or every one of them in order.
public func runUnittests(context: *Context, options: *Options)->s32 fail
{
    if options.module.isEmpty()
    {
        for suite in allSuites()
        {
            let code = try runSuite(context, options, suite, options.buildCfg.toString())
            if code != 0 do
                return code
        }

        return 0
    }

    for suite in allSuites()
    {
        if options.module == suite do
            return try runSuite(context, options, suite, options.buildCfg.toString())
    }

    Console.print("Unknown suite \"", options.module.toString(), "\". Available suites:")
    for suite in allSuites() do
        Console.print(" ", suite)
    Console.println()
    return 1
}

// Runs one suite in one configuration.
public func runSuite(context: *Context, options: *Options, suite: string, buildCfg: string)->s32 fail
{
    switch suite
    {
    case "cpp":

        // The compiler's own C++ tests are linked into the DevMode build only.
        if not options.devMode do
            return 0
        var arguments: Arguments
        arguments.add(["unittest", "--dev-full"])
        options.appendExtra(&arguments)
        return try context.runCompiler(arguments)

    case "lexer":
        let first = try runSourceSuite(context, options, "unittests/lexer", "Lexer", "lex-only", "--lex-only", buildCfg)
        if first != 0 do
            return first
        return try runSourceSuite(context, options, "unittests/errors/lexer", "Lexer", "lex-only", "--lex-only", buildCfg)

    case "parser":
        let first = try runSourceSuite(context, options, "unittests/parser", "Parser", "syntax-only", "--syntax-only", buildCfg)
        if first != 0 do
            return first
        return try runSourceSuite(context, options, "unittests/errors/parser", "Parser", "syntax-only", "--syntax-only", buildCfg)

    case "sema":
        let first = try runSourceSuite(context, options, "unittests/sema", "Sema", "sema-only", "--sema-only", buildCfg)
        if first != 0 do
            return first
        return try runSourceSuite(context, options, "unittests/errors/sema", "Sema", "sema-only", "--sema-only", buildCfg)

    case "jit":
        return try runSourceSuite(context, options, "unittests/jit", "Jit", "no-output", "--no-output", buildCfg)

    case "safety":
        return try runSourceSuite(context, options, "unittests/safety", "Safety", "no-output", "--no-output", buildCfg)

    case "sanity":
        return try runSourceSuite(context, options, "unittests/sanity", "Sanity", "no-output", "--no-output", buildCfg)

    case "native":

        // Native runs the whole pipeline, so it emits and executes a real artifact.
        let code = try runSourceSuite(context, options, "unittests/native", "Native", "executable", "", buildCfg)
        if code != 0 do
            return code
        for option in options.extra.values
        {
            let value = option.toString()
            if value == "--file-filter" or value == "-ff" or Utf8.startsWith(value, "--file-filter=") do
                return 0
        }

        return try verifyNativeTestRecovery(context, options, buildCfg)

    case "workspace":
        return try runWorkspaceSuite(context, options, buildCfg)
    }

    return 0
}

// Runs one directory of standalone suite sources.
private func runSourceSuite(context: *Context, options: *Options, relative: string, moduleNamespace: string, label: string, stage: string, buildCfg: string)->s32 fail
{
    let paths = context.artifactPaths(relative, label, buildCfg)

    var arguments: Arguments
    arguments.add(["test", "--artifact-kind", "executable"])
    arguments.add(["-d", Path.combine(context.binDir.toString(), relative).toString()])
    arguments.add(["--module-namespace", moduleNamespace])
    arguments.add(["--out-dir", paths.outDir.toString(), "--work-dir", paths.workDir.toString()])
    arguments.add(["--build-cfg", buildCfg])
    if stage.count != 0 do
        arguments.add([stage])

    options.appendExtra(&arguments)
    return try context.runCompiler(arguments)
}

// Expected failures run in a scratch subprocess: ordinary suite execution must remain green.
// A failed test can resume only while no scheduled callback still borrows its abandoned frame.
private func verifyNativeTestRecovery(context: *Context, options: *Options, buildCfg: string)->s32 fail
{
    let temporary = Path.combine(context.binDir.toString(), "unittests", ".tmp")
    let probeRoot = Path.combine(temporary.toString(), "native-recovery-probe")
    let scratch   = Path.combine(probeRoot.toString(), buildCfg)
    if Directory.exists(scratch) do
        try Directory.delete(scratch.toString(), recurse: true)
    for directory in [temporary, probeRoot, scratch]
    {
        if not Directory.exists(directory.toString()) do
            try Directory.create(directory.toString())
    }

    defer discard catch Directory.delete(scratch.toString(), recurse: true)

    for scenario in ["idle", "pending", "hardware"]
    {
        var body: String
        if scenario != "idle" do
            body.append(#raw """
            Swag.setWorkerCount(1)
            var borrowed = 42'u64
            var task: Swag.Task
            defer discard gate.raise()
            task.submit(func|&borrowed|()
            {
                discard entered.raise()
                while not gate.isRaised() do sleep(1)
                borrowed += 1
            })
            while not entered.isRaised() do sleep(1)
            """)
        body.append(scenario == "hardware" ? "\nraiseFault(0xC0000005, 0, 0, null)\n" : "\nSwag.panic(\"native recovery probe\", #curlocation)\n")

        let source     = Format.toString(#raw """
            #global private
            #[Swag.Foreign("kernel32", "Sleep")]
            func sleep(milliseconds: u32)
            #[Swag.Foreign("kernel32", "RaiseException")]
            func raiseFault(code, flags, count: u32, arguments: *void?)
            var entered: Swag.AtomicFlag
            var gate: Swag.AtomicFlag

            #test
            {
                if Swag.jit() do return
                %
            }
            #test
            {
                if not Swag.jit()
                {
                    Swag.print("native recovery continued\n")
                    Swag.drainWork()
                }
            }
            """, body.toString())
        let sourcePath = Path.combine(scratch.toString(), "recovery.swg")
        try File.writeAllBytes(sourcePath.toString(), cast(const [..] u8) source.toString())

        var command: Arguments
        command.add(["test", "--file", sourcePath.toString(), "--build-cfg", buildCfg])
        command.add(["--out-dir", Path.combine(scratch.toString(), "output").toString(), "--work-dir", Path.combine(scratch.toString(), "work").toString()])
        options.appendExtra(&command)
        command.add(["--run-timeout", "3"])

        var output: String
        let exitCode = try context.captureCompilerReport(&output, command)
        Console.println("Expected native test failure: ", scenario)
        Console.print(output.toString())

        let stopped      = Utf8.contains(output.toString(), "#test cannot resume while submitted work is unfinished")
        let continued    = Utf8.contains(output.toString(), "native recovery continued")
        let expectedStop = scenario != "idle"
        if exitCode == 0 or Utf8.contains(output.toString(), "did not finish within") or stopped != expectedStop or continued == expectedStop
        {
            Console.println("native test recovery did not stop or continue at the task lifetime boundary")
            return 1
        }
    }

    return 0
}

// Names one workspace suite module for `verb`.
//
// The three commands the suite runs differ by their verb alone, so they are named in one place
// rather than written out three times.
private func workspaceModuleCommand(verb: string, workspace: string, module: string, buildCfg: string)->Arguments
{
    var result: retval
    result.add([verb, "--workspace", workspace, "--workspace-module", module])
    result.add(["--build-cfg", buildCfg])
    return result
}

// Reports whether the test phase of one workspace test command compiled `module`.
//
// A test run builds the workspace first, so a dependent finds the interface a test compile never
// publishes. Both phases then report the same module, and only the test one states a test count:
// that is what tells a reused build apart from a reused test, without reading a file count that
// moves whenever the fixture gains a source.
private func testPhaseCompiled(output, module: string)->bool
{
    for line in Tokenize.splitLines(output)
    {
        if Utf8.contains(line, "workspace") do
            continue
        let reportsTests = Utf8.contains(line, " tests") or Utf8.contains(line, " passed") or Utf8.contains(line, " failed")
        if Utf8.contains(line, module) and reportsTests and not Utf8.contains(line, "up-to-date") do
            return true
    }

    return false
}

// Reports whether `output` states the artifact `name` as reused.
//
// The compiler separates its status fields with a bullet, or with '*' under '--log-ascii', so
// the check matches the two words on one line rather than pinning the glyph between them.
private func artifactReportedUpToDate(output, name: string)->bool
{
    for line in Tokenize.splitLines(output)
    {
        if Utf8.contains(line, "up-to-date") and Utf8.contains(line, name) do
            return true
    }

    return false
}

private func artifactReportedRelinked(output, name: string)->bool
{
    for line in Tokenize.splitLines(output)
    {
        if Utf8.contains(line, "relinked") and Utf8.contains(line, name) do
            return true
    }

    return false
}

// Counts permanent module report lines for one dependency. Progress frames are absent from captured
// output, so a repeated line proves that the dependency was reported more than once.
private func moduleReportCount(output, module: string)->u32
{
    var result: u32
    for line in Tokenize.splitLines(output)
    {
        if Utf8.contains(line, module) and (Utf8.contains(line, " files") or Utf8.contains(line, "up-to-date")) do
            result += 1
    }

    return result
}

// Checks that a workspace materializes only the dependency closure imported from another
// workspace and reads every local module directly from its own output.
private func verifyWorkspaceDependencyLayout(context: *Context, workspace: string)->s32
{
    let dependencyDirectory = Path.combine(workspace, ".dep")
    for dependency in ["core", "win32", "xinput"] where not Directory.exists(Path.combine(dependencyDirectory.toString(), dependency))
    {
        Console.println("Workspace did not materialize external dependency in '.dep': ", dependency)
        return 1
    }

    for module in ["api_export_provider", "api_static_provider", "runtime_context_base_static", "runtime_context_bridge_dll", "runtime_context_direct_static"] where Directory.exists(Path.combine(dependencyDirectory.toString(), module))
    {
        Console.println("Workspace materialized local module in '.dep': ", module)
        return 1
    }

    if Directory.exists(Path.combine(context.workspacePath("std").toString(), ".dep"))
    {
        Console.println("Standard workspace materialized local modules in '.dep'.")
        return 1
    }

    return 0
}

// Checks the compact spelling contract of the generated public API fixture.
private func verifyCompactExportedApi(workspace: string, buildCfg: string, targetArch: string)->s32 fail
{
    let exportDirectory = Path.combine(workspace, ".output", "api_export_provider", "export", buildCfg, targetArch)
    let generated       = try File.readAllText(Path.combine(exportDirectory.toString(), "api_export_provider.swg").toString())
    let wholeFile       = try File.readAllText(Path.combine(exportDirectory.toString(), "legacy.swg").toString())
    let staticDirectory = Path.combine(workspace, ".output", "api_static_provider", "static-library", buildCfg, targetArch)
    let staticApi       = try File.readAllText(Path.combine(staticDirectory.toString(), "api_static_provider.swg").toString())

    for redundant in ["#[Swag.", "namespace DepTools {}", "namespace DepTools.Deep {}", "namespace DepSharedRng {}", "namespace Shared {}"]
    {
        if not generated.contains(redundant) and not wholeFile.contains(redundant) do
            continue

        Console.println("Generated module API still contains redundant text: ", redundant)
        return 1
    }

    for compact in ["#[Discardable, Inline]", "#[Align(8)]"]
    {
        if generated.contains(compact) do
            continue

        Console.println("Generated module API is missing compact attribute list: ", compact)
        return 1
    }

    if not wholeFile.contains("#[Discardable, Inline]")
    {
        Console.println("Whole-file module API is missing compact attribute list: #[Discardable, Inline]")
        return 1
    }

    for redundant in ["#[Opaque]", "Opaque]", "Pack(8)", "NoDoc", "NoDuplicate"]
    {
        if not generated.contains(redundant) and not staticApi.contains(redundant) do
            continue

        Console.println("Generated module API still contains a producer-only attribute: ", redundant)
        return 1
    }

    if not staticApi.contains("#[Foreign, Discardable]") or not staticApi.contains("func depTriple(value: s32)->s32")
    {
        Console.println("Bodyless module API declaration lost a consumer attribute")
        return 1
    }

    let retainedBodyAttributes = "#[NoInline, Safety(.All, false), Sanity(.All, false), Optimize(false), Warning(\"all\", .Disable)]"
    if not staticApi.contains(retainedBodyAttributes) or not staticApi.contains("func(T) depMirror(value: T)->T => value")
    {
        Console.println("Exported function body lost its compilation attributes")
        return 1
    }

    return 0
}

// Checks the names and ownership boundaries of files published in a workspace output directory.
private func verifyWorkspaceArtifactLayout(workspace: string, buildCfg: string, targetArch: string)->s32 fail
{
    let executableDirectory = Path.combine(workspace, ".output", "consumer_exe", "executable", buildCfg, targetArch)
    if File.exists(Path.combine(executableDirectory.toString(), "consumer_exe.swg"))
    {
        Console.println("Workspace executable published a module API file.")
        return 1
    }

    if File.exists(Path.combine(executableDirectory.toString(), ".swc-deps")) or File.exists(Path.combine(executableDirectory.toString(), "consumer_exe.deps"))
    {
        Console.println("Workspace executable published dependency metadata.")
        return 1
    }

    let outputSources = try Directory.enumerateFiles(executableDirectory.toString(), ".swgsrc")
    for outputSource in outputSources
    {
        let name = Path.fileName(outputSource.fullName.toString()) orelse ""
        if Utf8.contains(name, ".gen.") or Utf8.contains(name, "-generated-source-")
        {
            Console.println("Non-debug workspace executable published generated source in '.output': ", name)
            return 1
        }
    }

    let intermediateDirectory = Path.combine(workspace, ".tmp", "consumer_exe", "executable", buildCfg, targetArch)
    var foundGeneratedSource: bool
    let generatedSources      = try Directory.enumerateFiles(intermediateDirectory.toString(), ".swgsrc")
    for generatedSource in generatedSources
    {
        let name = Path.fileName(generatedSource.fullName.toString()) orelse ""
        if Utf8.contains(name, ".gen.") do
            foundGeneratedSource = true
        if Utf8.contains(name, "-generated-source-")
        {
            Console.println("Workspace intermediate directory retained the old generated-source file name: ", name)
            return 1
        }
    }

    if not foundGeneratedSource
    {
        Console.println("Non-debug workspace executable did not write '<module>.gen.<number>.swgsrc' in '.tmp'.")
        return 1
    }

    let staticDirectory = Path.combine(workspace, ".output", "api_static_provider", "static-library", buildCfg, targetArch)
    if not File.exists(Path.combine(staticDirectory.toString(), ".swc-deps"))
    {
        Console.println("Workspace library did not publish '.swc-deps'.")
        return 1
    }

    if File.exists(Path.combine(staticDirectory.toString(), "api_static_provider.deps"))
    {
        Console.println("Workspace library retained '<module>.deps'.")
        return 1
    }

    return 0
}

// Checks that source-driven test compilations publish only reusable executable artifacts.
private func verifyWorkspaceTestArtifactLayout(workspace: string, buildCfg: string, targetArch: string, focused: bool)->s32 fail
{
    let outputDirectory = Path.combine(workspace, ".output")
    let outputFiles     = try Directory.enumerateFiles(outputDirectory.toString(), recurse: true)
    for outputFile in outputFiles
    {
        let name = Path.fileName(outputFile.fullName.toString()) orelse ""
        if Utf8.contains(name, ".test.dll") or Utf8.contains(name, ".test.lib")
        {
            Console.println("Workspace test published a library artifact: ", outputFile.fullName.toString())
            return 1
        }

        if name == ".swc-artifacts.test"
        {
            let fullName = outputFile.fullName.toString()
            if not Utf8.contains(fullName, "/test/") and not Utf8.contains(fullName, "\\test\\")
            {
                Console.println("Non-executable workspace test published an artifact manifest: ", outputFile.fullName.toString())
                return 1
            }
        }

        if focused and Utf8.contains(name, ".focused")
        {
            Console.println("Focused workspace test published an artifact in '.output': ", outputFile.fullName.toString())
            return 1
        }
    }

    let testDirectory = Path.combine(workspace, ".output", "consumer_exe", "test", buildCfg, targetArch)
    if not File.exists(Path.combine(testDirectory.toString(), "consumer_exe.test.exe")) or
       not File.exists(Path.combine(testDirectory.toString(), ".swc-artifacts.test"))
    {
        Console.println("Reusable workspace test executable or its manifest is missing.")
        return 1
    }

    // A file filter is an argument the executable reads, not a second executable. The run above
    // reused the published one, so nothing of its own may be left anywhere -- '.output' is
    // covered by the walk, and '.tmp' is where a filtered build used to put its copy.
    if focused
    {
        let focusedExecutable = Path.combine(workspace, ".tmp", "consumer_exe", "test", buildCfg, targetArch, "consumer_exe.test.focused.exe")
        if File.exists(focusedExecutable)
        {
            Console.println("Focused workspace test built an executable of its own: ", focusedExecutable.toString())
            return 1
        }
    }

    return 0
}

// Checks that a module's cached setup answers for the file the command finds, not the one an
// earlier command found: an edit to module.swg has to reach the very next build.
//
// The artifact name is decided by the setup alone, so a stale setup would rebuild the old
// executable under its old name and never produce the renamed one.
private func verifyModuleSetupCacheInvalidation(context: *Context, options: *Options, workspace: string, buildCfg: string)->s32 fail
{
    let scratch = Path.combine(workspace, ".tmp", "setup-cache-probe")
    if Directory.exists(scratch) do
        try Directory.delete(scratch.toString(), recurse: true)
    defer discard catch Directory.delete(scratch.toString(), recurse: true)

    let moduleDir = Path.combine(scratch.toString(), "modules", "probe")
    let sourceDir = Path.combine(moduleDir.toString(), "src")
    for directory in [scratch, Path.combine(scratch.toString(), "modules"), moduleDir, sourceDir] do
        try Directory.create(directory.toString())

    let moduleFile = Path.combine(moduleDir.toString(), "module.swg")
    try File.writeAllText(moduleFile.toString(), "#run\n{\n    let cfg = Swag.compiler().getBuildCfg()!\n    cfg.backendKind = .Executable\n}\n")
    try File.writeAllBytes(Path.combine(sourceDir.toString(), "main.swg").toString(), cast(const [..] u8) "#main\n{\n}\n")

    var built = workspaceModuleCommand("build", scratch.toString(), "probe", buildCfg)
    options.appendExtra(&built)
    let firstCode = try context.runCompiler(built)
    if firstCode != 0 do
        return firstCode

    let cacheFile = Path.combine(scratch.toString(), ".tmp", "probe", Format.toString(".swc-setup-%", buildCfg).toString())
    if not File.exists(cacheFile)
    {
        Console.println("Workspace build did not cache the module setup: ", cacheFile.toString())
        return 1
    }

    try File.writeAllText(moduleFile.toString(), "#run\n{\n    let cfg = Swag.compiler().getBuildCfg()!\n    cfg.backendKind = .Executable\n    cfg.name = \"renamed\"\n}\n")

    let secondCode = try context.runCompiler(built)
    if secondCode != 0 do
        return secondCode

    let renamed = Path.combine(scratch.toString(), ".output", "probe", "executable", buildCfg, options.targetArch.toString(), "renamed.exe")
    if not File.exists(renamed)
    {
        Console.println("An edited module.swg did not reach the next build's setup: ", renamed.toString())
        return 1
    }

    return 0
}

/*
A module built on its own caches its setup exactly like a module of a workspace does.

That module has no workspace to keep the cache in, so it keeps one under its own root, and `clean`
empties it there. The scenario walks the whole contract: a first build writes the cache, an edited
`module.swg` reaches the next build, and `clean` leaves nothing behind.
*/
private func verifyStandaloneModuleSetupCache(context: *Context, options: *Options, workspace: string, buildCfg: string)->s32 fail
{
    let moduleDir = Path.combine(workspace, ".tmp", "standalone-setup-probe")
    if Directory.exists(moduleDir) do
        try Directory.delete(moduleDir.toString(), recurse: true)
    defer discard catch Directory.delete(moduleDir.toString(), recurse: true)

    let sourceDir = Path.combine(moduleDir.toString(), "src")
    for directory in [moduleDir, sourceDir] do
        try Directory.create(directory.toString())

    let moduleFile = Path.combine(moduleDir.toString(), "module.swg")
    try File.writeAllText(moduleFile.toString(), "#run\n{\n    let cfg = Swag.compiler().getBuildCfg()!\n    cfg.backendKind = .Executable\n}\n")
    try File.writeAllBytes(Path.combine(sourceDir.toString(), "main.swg").toString(), cast(const [..] u8) "#main\n{\n}\n")

    var built: Arguments
    built.add(["build", "--module-file", moduleFile.toString(), "--directory", "src"])
    built.add(["--build-cfg", buildCfg])
    options.appendExtra(&built)
    let firstCode = try context.runCompiler(built)
    if firstCode != 0 do
        return firstCode

    let cacheFile = Path.combine(moduleDir.toString(), ".tmp", Format.toString(".swc-setup-%", buildCfg).toString())
    if not File.exists(cacheFile)
    {
        Console.println("A module built on its own did not cache its setup: ", cacheFile.toString())
        return 1
    }

    try File.writeAllText(moduleFile.toString(), "#run\n{\n    let cfg = Swag.compiler().getBuildCfg()!\n    cfg.backendKind = .Executable\n    cfg.name = \"standalone\"\n}\n")

    // A module built on its own names its output directory after the command that produced it, so
    // what the build reports is what says the new name reached the setup.
    let output = try context.captureCompiler(built)
    Console.print(output.toString())
    if not Utf8.contains(output.toString(), "standalone.exe")
    {
        Console.println("An edited module.swg did not reach the next standalone build's setup")
        return 1
    }

    var cleaned: Arguments
    cleaned.add(["clean", "--module-file", moduleFile.toString()])
    options.appendExtra(&cleaned)
    let cleanCode = try context.runCompiler(cleaned)
    if cleanCode != 0 do
        return cleanCode

    if File.exists(cacheFile)
    {
        Console.println("Cleaning a module built on its own left its setup cache behind: ", cacheFile.toString())
        return 1
    }

    return 0
}

// A source gate and a typed tag both change the executable. Reusing it with another tag set
// must rebuild, and returning to the original set must restore the original behavior.
private func verifyWorkspaceTagCache(context: *Context, options: *Options, workspace, buildCfg: string)->s32 fail
{
    for state in ["disabled", "0", "42", "42", "disabled"]
    {
        var command = workspaceModuleCommand("run", workspace, "tag_cache", buildCfg)
        options.appendExtra(&command)
        if state != "disabled" do
            command.add(["--tag", "cache.enabled"])
        if state == "42" do
            command.add(["--tag", "cache.value: u32 = 42"])
        let output = try context.captureCompiler(command)
        Console.print(output.toString())
        let expected = Format.toString("cache-tag=%", state)
        if not Utf8.contains(output.toString(), expected.toString())
        {
            Console.println("Workspace artifact reused a different tag set; expected ", expected.toString())
            return 1
        }
    }

    return 0
}

// A build with '--debug' is another program. It lives beside the plain build under
// '<config>-debug', takes in dependencies built the same way, and alternating the two rebuilds
// neither. An explicit optimization level changes the program without changing its directory, so a
// reused artifact has to match it too.
private func verifyWorkspaceDebugVariant(context: *Context, options: *Options, workspace, buildCfg: string)->s32 fail
{
    var plain = workspaceModuleCommand("build", workspace, "standalone_exe", buildCfg)
    options.appendExtra(&plain)
    var debug = workspaceModuleCommand("build", workspace, "standalone_exe", buildCfg)
    debug.add(["--debug"])
    options.appendExtra(&debug)

    let plainCode = try context.runCompiler(plain)
    if plainCode != 0 do
        return plainCode
    let debugCode = try context.runCompiler(debug)
    if debugCode != 0 do
        return debugCode

    let debugCfg       = Format.toString("%-debug", buildCfg)
    let targetArch     = options.targetArch.toString()
    let plainDirectory = Path.combine(workspace, ".output", "standalone_exe", "executable", buildCfg, targetArch)
    let debugDirectory = Path.combine(workspace, ".output", "standalone_exe", "executable", debugCfg.toString(), targetArch)
    if File.exists(Path.combine(plainDirectory.toString(), "standalone_exe.pdb").toString())
    {
        Console.println("A plain workspace build published debug information.")
        return 1
    }

    if not File.exists(Path.combine(debugDirectory.toString(), "standalone_exe.pdb").toString())
    {
        Console.println("A '--debug' workspace build did not publish its PDB under '", debugCfg.toString(), "'.")
        return 1
    }

    let coreDebug = Path.combine(context.workspaceOutput("std").toString(), "core", "static-library", debugCfg.toString(), targetArch)
    if not Directory.exists(coreDebug.toString())
    {
        Console.println("A '--debug' workspace build did not take in a standard library built with debug information.")
        return 1
    }

    for 2
    {
        let plainOutput = try context.captureCompiler(plain)
        Console.print(plainOutput.toString())
        let debugOutput = try context.captureCompiler(debug)
        Console.print(debugOutput.toString())
        if not artifactReportedUpToDate(plainOutput.toString(), "standalone_exe.exe") or not artifactReportedUpToDate(debugOutput.toString(), "standalone_exe.exe")
        {
            Console.println("Alternating a plain and a '--debug' workspace build rebuilt one of them.")
            return 1
        }
    }

    var unoptimized = workspaceModuleCommand("build", workspace, "tag_cache", buildCfg)
    unoptimized.add(["--optim-level", "0"])
    options.appendExtra(&unoptimized)
    var optimized = workspaceModuleCommand("build", workspace, "tag_cache", buildCfg)
    options.appendExtra(&optimized)

    let optimizedCode = try context.runCompiler(optimized)
    if optimizedCode != 0 do
        return optimizedCode

    let unoptimizedOutput = try context.captureCompiler(unoptimized)
    Console.print(unoptimizedOutput.toString())
    if artifactReportedUpToDate(unoptimizedOutput.toString(), "tag_cache.exe")
    {
        Console.println("A workspace build reused an artifact built at another optimization level.")
        return 1
    }

    let repeatedOutput = try context.captureCompiler(unoptimized)
    Console.print(repeatedOutput.toString())
    if not artifactReportedUpToDate(repeatedOutput.toString(), "tag_cache.exe")
    {
        Console.println("An unchanged workspace build at an explicit optimization level rebuilt its artifact.")
        return 1
    }

    return 0
}

// An executable takes its dependencies' code in, and its stack traces name their frames as they name
// its own: a panic raised inside a dependency reports the dependency's function.
private func verifyWorkspaceDependencyStackTrace(context: *Context, options: *Options, workspace, buildCfg: string)->s32 fail
{
    var command = workspaceModuleCommand("run", workspace, "standalone_exe", buildCfg)
    command.add(["--run-arg", "workspace.panic-in-dependency"])
    options.appendExtra(&command)

    var output: String
    let exitCode = try context.captureCompilerReport(&output, command)
    Console.print(output.toString())
    if exitCode == 0 or not Utf8.contains(output.toString(), "raised by a dependency")
    {
        Console.println("A panic inside a linked dependency did not stop the executable with its report.")
        return 1
    }

    if not Utf8.contains(output.toString(), "ctxSharedPanic")
    {
        Console.println("The stack trace of a panic inside a linked dependency did not name the dependency's frame.")
        return 1
    }

    return 0
}

// Emits a scratch-only writer without standard-module imports. The replacement is source text
// for an ordinary string literal, so its quotes and newlines are already escaped by the caller.
private func workspaceSourceRewrite(path, replacement: string)->String
{
    return Format.toString(#raw """
        #[Swag.Foreign("kernel32", "CreateFileA")]
        func createFile(path: const [*] u8, access, share: u32, security: *void?, creation, flags: u32, template: *void?)->*void?
        #[Swag.Foreign("kernel32", "WriteFile")]
        func writeFile(file: *void?, bytes: const [*] u8, count: u32, written: *u32, overlapped: *void?)->bool
        #[Swag.Foreign("kernel32", "CloseHandle")]
        func closeHandle(file: *void?)->bool

        func rewriteSource()
        {
            let path = #raw "%"
            let content = "%"
            let file = createFile(path.buffer, 0x40000000, 1, null, 2, 0, null)
            Swag.assert(cast(u64) file != Swag.U64.Max)
            var written: u32
            let result = writeFile(file, content.buffer, cast(u32) content.count, &written, null)
            let closed = closeHandle(file)
            Swag.assert(result and closed and written == content.count)
        }
        """, path, replacement)
}

// A #run edits a source only after its old constant has been read. Publication happens later,
// so comparing the source with the manifest's write time would wrongly reuse the old executable.
private func verifyWorkspaceSourceEditDuringBuild(context: *Context, options: *Options, workspace, buildCfg: string)->s32 fail
{
    let scratch = Path.combine(workspace, ".tmp", "source-edit-during-build-probe")
    if Directory.exists(scratch) do
        try Directory.delete(scratch.toString(), recurse: true)
    defer discard catch Directory.delete(scratch.toString(), recurse: true)

    let moduleDir = Path.combine(scratch.toString(), "modules", "probe")
    let sourceDir = Path.combine(moduleDir.toString(), "src")
    for directory in [scratch, Path.combine(scratch.toString(), "modules"), moduleDir, sourceDir] do
        try Directory.create(directory.toString())

    let modulePath = Path.combine(moduleDir.toString(), "module.swg")
    let mainPath   = Path.combine(sourceDir.toString(), "main.swg")
    let valuePath  = Path.combine(sourceDir.toString(), "value.swg")
    try File.writeAllText(valuePath.toString(), "const BuildValue = 1\n")
    try File.writeAllText(modulePath.toString(), "#run { Swag.compiler().getBuildCfg()!.backendKind = .Executable }\n")

    var source = workspaceSourceRewrite(valuePath.toString(), "const BuildValue = 2\\n")
    source.append(#raw """

        #run { if BuildValue == 1 do rewriteSource() }

        #main
        {
            if BuildValue == 1 do Swag.print("source-edit-value=1\n")
            else do Swag.print("source-edit-value=2\n")
        }
        """)
    try File.writeAllBytes(mainPath.toString(), cast(const [..] u8) source.toString())

    var command = workspaceModuleCommand("run", scratch.toString(), "probe", buildCfg)
    options.appendExtra(&command)
    var iteration: u32
    for expected in ["1", "2", "2"]
    {
        let output = try context.captureCompiler(command)
        Console.print(output.toString())
        let marker = Format.toString("source-edit-value=%", expected)
        if not Utf8.contains(output.toString(), marker.toString())
        {
            Console.println("A source edited during compilation did not reach the next workspace run; expected ", marker.toString())
            return 1
        }

        if iteration == 2 and not Utf8.contains(output.toString(), "up-to-date")
        {
            Console.println("An unchanged source rebuilt after the overlapping edit had been consumed.")
            return 1
        }

        iteration += 1
    }

    // Setup has its own cache, written before the artifact. It must not stamp the replacement
    // module.swg as evidence for the configuration read from the source that replaced itself.
    var setupSource = workspaceSourceRewrite(modulePath.toString(), "#run { let cfg = Swag.compiler().getBuildCfg()!; cfg.backendKind = .Executable; cfg.name = \\\"after\\\" }\\n")
    setupSource.append("\n#run { let cfg = Swag.compiler().getBuildCfg()!; cfg.backendKind = .Executable; cfg.name = \"before\"; rewriteSource() }\n")
    try File.writeAllBytes(modulePath.toString(), cast(const [..] u8) setupSource.toString())
    try File.writeAllText(mainPath.toString(), "#main { }\n")
    for expected in ["before.exe", "after.exe"]
    {
        let output = try context.captureCompiler(command)
        Console.print(output.toString())
        if not Utf8.contains(output.toString(), expected)
        {
            Console.println("A setup edited during evaluation did not reach the next workspace run; expected ", expected)
            return 1
        }
    }

    // An imported API has already been captured when #run executes. Its producer's artifact
    // manifest remains unchanged, so the API needs its own read boundary in the consumer cache.
    let providerWorkspace = Path.combine(scratch.toString(), "provider-workspace")
    let providerModules   = Path.combine(providerWorkspace.toString(), "modules")
    let providerModule    = Path.combine(providerModules.toString(), "provider")
    let providerSource    = Path.combine(providerModule.toString(), "src")
    for directory in [providerWorkspace, providerModules, providerModule, providerSource] do
        try Directory.create(directory.toString())
    try File.writeAllBytes(Path.combine(providerModule.toString(), "module.swg").toString(), cast(const [..] u8) "#run { let cfg = Swag.compiler().getBuildCfg()!; cfg.backendKind = .Export; cfg.moduleNamespace = \"ReadApi\" }\n")
    try File.writeAllBytes(Path.combine(providerSource.toString(), "value.swg").toString(), cast(const [..] u8) "public const Value = 1\n")
    var producer = workspaceModuleCommand("build", providerWorkspace.toString(), "provider", buildCfg)
    options.appendExtra(&producer)
    let providerOutput = try context.captureCompiler(producer)
    Console.print(providerOutput.toString())

    let dependencyRoot = Path.combine(providerWorkspace.toString(), ".output")
    let apiPath        = Path.combine(dependencyRoot.toString(), "provider", "export", buildCfg, options.targetArch.toString(), "provider.swg")
    let consumerSetup  = Format.toString(#raw """
        #import("provider", location: "%")
        #import("core", location: "swag@std")
        #run { Swag.compiler().getBuildCfg()!.backendKind = .Executable }
        """, dependencyRoot.toString())
    try File.writeAllBytes(modulePath.toString(), cast(const [..] u8) consumerSetup.toString())
    var apiConsumer = workspaceSourceRewrite(apiPath.toString(), "#global namespace ReadApi\\n#global public\\nconst Value = 2\\n")
    apiConsumer.append(#raw """

        #run { if ReadApi.Value == 1 do rewriteSource() }
        #main
        {
            if ReadApi.Value == 1 do Swag.print("api-edit-value=1\n")
            else do Swag.print("api-edit-value=2\n")
        }
        """)
    try File.writeAllBytes(mainPath.toString(), cast(const [..] u8) apiConsumer.toString())
    iteration = 0
    for expected in ["1", "2", "2"]
    {
        let output = try context.captureCompiler(command)
        Console.print(output.toString())
        let marker = Format.toString("api-edit-value=%", expected)
        if not Utf8.contains(output.toString(), marker.toString()) or (iteration == 2 and not Utf8.contains(output.toString(), "up-to-date"))
        {
            Console.println("An API edited after capture did not reach the next workspace run; expected ", marker.toString())
            return 1
        }

        iteration += 1
    }

    let deletingConsumer = Format.toString(#raw """
        #run
        {
            if #defined(ReadApi.Value)
            {
                let path = #raw "%"
                expect Core.File.delete(path)
            }
        }
        #main
        {
            if #defined(ReadApi.Value) do Swag.print("api-membership=present\n")
            else do Swag.print("api-membership=absent\n")
        }
        """, apiPath.toString())
    try File.writeAllBytes(mainPath.toString(), cast(const [..] u8) deletingConsumer.toString())
    iteration = 0
    for expected in ["present", "absent", "absent"]
    {
        let output = try context.captureCompiler(command)
        Console.print(output.toString())
        let marker = Format.toString("api-membership=%", expected)
        if not Utf8.contains(output.toString(), marker.toString()) or (iteration == 2 and not Utf8.contains(output.toString(), "up-to-date"))
        {
            Console.println("An API file removed after capture did not reach the next workspace run; expected ", marker.toString())
            return 1
        }

        iteration += 1
    }

    return 0
}

// A local publisher runs after external mirroring, then installs a rebuilt DLL before the
// consumer enters compilation. The unchanged public API cannot stand in for native freshness.
private func verifyWorkspaceNativeReadDuringBuild(context: *Context, options: *Options, workspace, buildCfg: string)->s32 fail
{
    let scratch = Path.combine(workspace, ".tmp", "native-read-during-build-probe")
    if Directory.exists(scratch) do
        try Directory.delete(scratch.toString(), recurse: true)
    defer discard catch Directory.delete(scratch.toString(), recurse: true)
    try Directory.create(scratch.toString())
    let providerWorkspace = Path.combine(scratch.toString(), "provider-workspace")
    let consumerWorkspace = Path.combine(scratch.toString(), "consumer-workspace")
    for directory in [providerWorkspace, consumerWorkspace]
    {
        try Directory.create(directory.toString())
        try Directory.create(Path.combine(directory.toString(), "modules").toString())
    }

    let providerModule = Path.combine(providerWorkspace.toString(), "modules", "provider")
    let writerModule   = Path.combine(consumerWorkspace.toString(), "modules", "writer")
    let consumerModule = Path.combine(consumerWorkspace.toString(), "modules", "consumer")
    for directory in [providerModule, writerModule, consumerModule]
    {
        try Directory.create(directory.toString())
        try Directory.create(Path.combine(directory.toString(), "src").toString())
    }

    let providerSource = Path.combine(providerModule.toString(), "src", "value.swg")
    try File.writeAllBytes(Path.combine(providerModule.toString(), "module.swg").toString(), cast(const [..] u8) "#run { let cfg = Swag.compiler().getBuildCfg()!; cfg.backendKind = .SharedLibrary; cfg.moduleNamespace = \"NativeReadApi\" }\n")
    try File.writeAllText(providerSource.toString(), "public func value()->s32 => 1\n")
    var producer = workspaceModuleCommand("build", providerWorkspace.toString(), "provider", buildCfg)
    options.appendExtra(&producer)
    let providerOutput = try context.captureCompiler(producer)
    Console.print(providerOutput.toString())

    let dependencyRoot  = Path.combine(providerWorkspace.toString(), ".output")
    let published       = Path.combine(dependencyRoot.toString(), "provider")
    let nativeOutput    = Path.combine(published.toString(), "shared-library", buildCfg, options.targetArch.toString())
    let exportPath      = Path.combine(nativeOutput.toString(), "provider.swg")
    let originalApi     = try File.readAllBytes(exportPath.toString())
    let originalApiTime = (try File.info(exportPath.toString())).lastWriteTime

    let replacementWorkspace = Path.combine(scratch.toString(), "replacement-workspace")
    let replacementModules   = Path.combine(replacementWorkspace.toString(), "modules")
    let replacementModule    = Path.combine(replacementModules.toString(), "provider")
    let replacementSource    = Path.combine(replacementModule.toString(), "src")
    for directory in [replacementWorkspace, replacementModules, replacementModule, replacementSource] do
        try Directory.create(directory.toString())
    try File.writeAllBytes(Path.combine(replacementModule.toString(), "module.swg").toString(), cast(const [..] u8) "#run { let cfg = Swag.compiler().getBuildCfg()!; cfg.backendKind = .SharedLibrary; cfg.moduleNamespace = \"NativeReadApi\" }\n")
    try File.writeAllBytes(Path.combine(replacementSource.toString(), "value.swg").toString(), cast(const [..] u8) "public func value()->s32 => 2\n")
    var replacement = workspaceModuleCommand("build", replacementWorkspace.toString(), "provider", buildCfg)
    options.appendExtra(&replacement)
    let replacementOutput = try context.captureCompiler(replacement)
    Console.print(replacementOutput.toString())
    let replacementNative = Path.combine(replacementWorkspace.toString(), ".output", "provider", "shared-library", buildCfg, options.targetArch.toString())
    let replacementApi    = try File.readAllBytes(Path.combine(replacementNative.toString(), "provider.swg").toString())
    if replacementApi.toSlice() != originalApi.toSlice()
    {
        Console.println("The rebuilt native dependency changed its public API")
        return 1
    }

    try File.writeAllBytes(Path.combine(writerModule.toString(), "module.swg").toString(), cast(const [..] u8) "#import(\"core\", location: \"swag@std\")\n#run { let cfg = Swag.compiler().getBuildCfg()!; cfg.backendKind = .Export; cfg.moduleNamespace = \"NativeWriter\" }\n")
    let writer     = workspaceNativePublisher(replacementNative.toString(), nativeOutput.toString())
    let writerPath = Path.combine(writerModule.toString(), "src", "main.swg")
    try File.writeAllText(writerPath.toString(), "public const Marker = 1\n")
    let consumerSetup = Format.toString(#raw """
        #import("writer")
        #import("provider", location: "%", link: "shared-library")
        #run { Swag.compiler().getBuildCfg()!.backendKind = .Executable }
        """, dependencyRoot.toString())
    try File.writeAllBytes(Path.combine(consumerModule.toString(), "module.swg").toString(), cast(const [..] u8) consumerSetup.toString())
    try File.writeAllBytes(Path.combine(consumerModule.toString(), "src", "main.swg").toString(), cast(const [..] u8) #raw """
        const Captured = #run NativeReadApi.value()
        #main
        {
            if Captured == 1 do Swag.print("native-read-value=1\n")
            else do Swag.print("native-read-value=2\n")
        }
        """)

    var command = workspaceModuleCommand("run", consumerWorkspace.toString(), "consumer", buildCfg)
    options.appendExtra(&command)
    for warm in [false, true]
    {
        let output = try context.captureCompiler(command)
        Console.print(output.toString())
        if not Utf8.contains(output.toString(), "native-read-value=1") or (warm and not Utf8.contains(output.toString(), "consumer • up-to-date"))
        {
            Console.println("An unchanged native dependency did not reuse the first workspace build")
            return 1
        }
    }

    try File.writeAllBytes(writerPath.toString(), cast(const [..] u8) writer.toString())
    var iteration: u32
    for expected in ["1", "2", "2"]
    {
        let output = try context.captureCompiler(command)
        Console.print(output.toString())
        let currentApi     = try File.readAllBytes(exportPath.toString())
        let currentApiTime = (try File.info(exportPath.toString())).lastWriteTime
        if currentApi.toSlice() != originalApi.toSlice() or currentApiTime != originalApiTime
        {
            Console.println("The native dependency probe changed its stable API")
            return 1
        }

        let marker = Format.toString("native-read-value=%", expected)
        if not Utf8.contains(output.toString(), marker.toString()) or (iteration == 2 and not Utf8.contains(output.toString(), "consumer • up-to-date"))
        {
            Console.println("A dependency rebuilt after mirroring did not reach the next workspace run; expected ", marker.toString())
            return 1
        }

        iteration += 1
    }

    return 0
}

// A private implementation edit changes the producer's native image, but not the interface that
// ordinary shared-library consumers compile against. Those consumers stay reusable; consumers
// that incorporated static code or ran the dependency at compile time still invalidate.
private func verifyPrivateDependencyInvalidation(context: *Context, options: *Options, workspace, buildCfg: string)->s32 fail
{
    let scratch = Path.combine(workspace, ".tmp", "private-dependency-invalidation-probe")
    if Directory.exists(scratch) do
        try Directory.delete(scratch.toString(), recurse: true)
    defer discard catch Directory.delete(scratch.toString(), recurse: true)

    let modules = Path.combine(scratch.toString(), "modules")
    try Directory.create(scratch.toString())
    try Directory.create(modules.toString())
    for module in ["provider", "middle", "leaf", "compile_time", "dynamic_consumer", "static_provider", "static_consumer", "incremental_static_consumer"]
    {
        let moduleDirectory = Path.combine(modules.toString(), module)
        try Directory.create(moduleDirectory.toString())
        try Directory.create(Path.combine(moduleDirectory.toString(), "src").toString())
    }

    try File.writeAllText(Path.combine(modules.toString(), "provider", "module.swg").toString(), "#run { let cfg = Swag.compiler().getBuildCfg()!; cfg.backendKind = .SharedLibrary; cfg.moduleNamespace = \"Provider\" }\n")
    let providerSource = Path.combine(modules.toString(), "provider", "src", "main.swg")
    try File.writeAllText(providerSource.toString(), "private func privateValue()->s32 => 1\npublic func value()->s32 => privateValue()\n")

    try File.writeAllText(Path.combine(modules.toString(), "middle", "module.swg").toString(), "#import(\"provider\")\n#run { let cfg = Swag.compiler().getBuildCfg()!; cfg.backendKind = .SharedLibrary; cfg.moduleNamespace = \"Middle\" }\n")
    try File.writeAllText(Path.combine(modules.toString(), "middle", "src", "main.swg").toString(), "public func value()->s32 => Provider.value()\n")

    try File.writeAllText(Path.combine(modules.toString(), "leaf", "module.swg").toString(), "#import(\"middle\")\n#run { let cfg = Swag.compiler().getBuildCfg()!; cfg.backendKind = .SharedLibrary; cfg.moduleNamespace = \"Leaf\" }\n")
    try File.writeAllText(Path.combine(modules.toString(), "leaf", "src", "main.swg").toString(), "public func value()->s32 => Middle.value()\n")

    try File.writeAllText(Path.combine(modules.toString(), "compile_time", "module.swg").toString(), "#import(\"provider\")\n#run { let cfg = Swag.compiler().getBuildCfg()!; cfg.backendKind = .Export; cfg.moduleNamespace = \"CompileTime\" }\n")
    try File.writeAllText(Path.combine(modules.toString(), "compile_time", "src", "main.swg").toString(), "public const Captured = #run Provider.value()\n")

    try File.writeAllText(Path.combine(modules.toString(), "dynamic_consumer", "module.swg").toString(), "#import(\"provider\", link: \"shared-library\")\n#run { let cfg = Swag.compiler().getBuildCfg()!; cfg.backendKind = .Executable; cfg.publishDependencies = true }\n")
    try File.writeAllText(Path.combine(modules.toString(), "dynamic_consumer", "src", "main.swg").toString(), "#main { if Provider.value() == 1 do Swag.print(\"incremental-value=1\\n\") else do Swag.print(\"incremental-value=2\\n\") }\n")

    try File.writeAllText(Path.combine(modules.toString(), "static_provider", "module.swg").toString(), "#run { let cfg = Swag.compiler().getBuildCfg()!; cfg.backendKind = .StaticLibrary; cfg.moduleNamespace = \"StaticProvider\" }\n")
    let staticProviderSource = Path.combine(modules.toString(), "static_provider", "src", "main.swg")
    try File.writeAllText(staticProviderSource.toString(), "private func privateValue()->s32 => 1\npublic func value()->s32 => privateValue()\n")

    try File.writeAllText(Path.combine(modules.toString(), "static_consumer", "module.swg").toString(), "#import(\"static_provider\")\n#run { let cfg = Swag.compiler().getBuildCfg()!; cfg.backendKind = .SharedLibrary; cfg.moduleNamespace = \"StaticConsumer\" }\n")
    try File.writeAllText(Path.combine(modules.toString(), "static_consumer", "src", "main.swg").toString(), "public func value()->s32 => StaticProvider.value()\n")

    try File.writeAllText(Path.combine(modules.toString(), "incremental_static_consumer", "module.swg").toString(), "#import(\"static_provider\")\n#run { Swag.compiler().getBuildCfg()!.backendKind = .Executable }\n")
    try File.writeAllText(Path.combine(modules.toString(), "incremental_static_consumer", "src", "main.swg").toString(), "#main { if StaticProvider.value() == 1 do Swag.print(\"static-incremental-value=1\\n\") else do Swag.print(\"static-incremental-value=2\\n\") }\n")

    var leaf = workspaceModuleCommand("build", scratch.toString(), "leaf", buildCfg)
    options.appendExtra(&leaf)
    let firstLeafCode = try context.runCompiler(leaf)
    if firstLeafCode != 0 do
        return firstLeafCode

    var compileTime = workspaceModuleCommand("build", scratch.toString(), "compile_time", buildCfg)
    options.appendExtra(&compileTime)
    let firstCompileTimeCode = try context.runCompiler(compileTime)
    if firstCompileTimeCode != 0 do
        return firstCompileTimeCode

    var dynamicConsumer = workspaceModuleCommand("run", scratch.toString(), "dynamic_consumer", buildCfg)
    dynamicConsumer.add(["--incremental"])
    options.appendExtra(&dynamicConsumer)
    let firstDynamicOutput = try context.captureCompiler(dynamicConsumer)
    Console.print(firstDynamicOutput.toString())
    if not Utf8.contains(firstDynamicOutput.toString(), "incremental-value=1")
    {
        Console.println("The initial incremental executable did not run with its shared dependency")
        return 1
    }

    var staticConsumer = workspaceModuleCommand("build", scratch.toString(), "static_consumer", buildCfg)
    options.appendExtra(&staticConsumer)
    let firstStaticConsumerCode = try context.runCompiler(staticConsumer)
    if firstStaticConsumerCode != 0 do
        return firstStaticConsumerCode

    var incrementalStaticConsumer = workspaceModuleCommand("run", scratch.toString(), "incremental_static_consumer", buildCfg)
    incrementalStaticConsumer.add(["--incremental"])
    options.appendExtra(&incrementalStaticConsumer)
    let firstIncrementalStaticOutput = try context.captureCompiler(incrementalStaticConsumer)
    Console.print(firstIncrementalStaticOutput.toString())
    if not Utf8.contains(firstIncrementalStaticOutput.toString(), "static-incremental-value=1")
    {
        Console.println("The initial incremental executable did not run with its static dependency")
        return 1
    }

    let incrementalObject = Path.combine(scratch.toString(), ".tmp", "incremental_static_consumer", "executable", buildCfg, options.targetArch.toString(), "incremental_static_consumer_00.obj")
    if not File.exists(incrementalObject.toString())
    {
        Console.println("The incremental executable did not publish its link object")
        return 1
    }
    let originalIncrementalObjectTime = (try File.info(incrementalObject.toString())).lastWriteTime

    let providerOutput = Path.combine(scratch.toString(), ".output", "provider", "shared-library", buildCfg, options.targetArch.toString())
    let providerApi    = Path.combine(providerOutput.toString(), "provider.swg")
    let originalApi    = try File.readAllBytes(providerApi.toString())
    let originalTime   = (try File.info(providerApi.toString())).lastWriteTime

    try File.writeAllText(providerSource.toString(), "private func privateValue()->s32 => 2\npublic func value()->s32 => privateValue()\n")
    let leafOutput = try context.captureCompiler(leaf)
    Console.print(leafOutput.toString())

    let currentApi  = try File.readAllBytes(providerApi.toString())
    let currentTime = (try File.info(providerApi.toString())).lastWriteTime
    if currentApi.toSlice() != originalApi.toSlice() or currentTime != originalTime
    {
        Console.println("A private implementation edit changed the provider's stable public API publication.")
        return 1
    }

    for artifact in ["middle.dll", "leaf.dll"] where not artifactReportedUpToDate(leafOutput.toString(), artifact)
    {
        Console.println("A private dependency edit recompiled an interface-stable library: ", artifact)
        return 1
    }

    let dynamicOutput = try context.captureCompiler(dynamicConsumer)
    Console.print(dynamicOutput.toString())
    if not artifactReportedUpToDate(dynamicOutput.toString(), "dynamic_consumer.exe") or not Utf8.contains(dynamicOutput.toString(), "incremental-value=2")
    {
        Console.println("Incremental mode did not reuse an executable with a fresh interface-compatible shared dependency")
        return 1
    }

    let compileTimeOutput = try context.captureCompiler(compileTime)
    Console.print(compileTimeOutput.toString())
    if artifactReportedUpToDate(compileTimeOutput.toString(), "compile_time")
    {
        Console.println("A module reused compile-time results from an older native dependency generation.")
        return 1
    }

    try File.writeAllText(staticProviderSource.toString(), "private func privateValue()->s32 => 2\npublic func value()->s32 => privateValue()\n")
    let staticConsumerOutput = try context.captureCompiler(staticConsumer)
    Console.print(staticConsumerOutput.toString())
    if artifactReportedUpToDate(staticConsumerOutput.toString(), "static_consumer.dll")
    {
        Console.println("A shared library reused code from an older static dependency generation.")
        return 1
    }

    let incrementalStaticOutput = try context.captureCompiler(incrementalStaticConsumer)
    Console.print(incrementalStaticOutput.toString())
    if not artifactReportedRelinked(incrementalStaticOutput.toString(), "incremental_static_consumer.exe") or not Utf8.contains(incrementalStaticOutput.toString(), "static-incremental-value=2")
    {
        Console.println("Incremental relinking did not incorporate the rebuilt static dependency")
        return 1
    }
    if (try File.info(incrementalObject.toString())).lastWriteTime != originalIncrementalObjectTime
    {
        Console.println("Incremental relinking recompiled the executable's unchanged object")
        return 1
    }

    let warmIncrementalStaticOutput = try context.captureCompiler(incrementalStaticConsumer)
    Console.print(warmIncrementalStaticOutput.toString())
    if not artifactReportedUpToDate(warmIncrementalStaticOutput.toString(), "incremental_static_consumer.exe") or not Utf8.contains(warmIncrementalStaticOutput.toString(), "static-incremental-value=2")
    {
        Console.println("The incrementally relinked executable was not reusable")
        return 1
    }

    return 0
}

private func incrementalFunctionCacheSource(seed: u64, marker: u32)->String
{
    return Format.toString(#raw """
        #global private

        #[Swag.NoInline]
        func stable(value: u64)->u64
        {
            var result = value
            result = (result << 7) ^ (result >> 3) ^ 0x9e3779b97f4a7c15
            result = (result << 5) ^ (result >> 11) ^ 0xbf58476d1ce4e5b9
            result = (result << 9) ^ (result >> 13) ^ 0x94d049bb133111eb
            result = (result << 3) ^ (result >> 17) ^ 0x2545f4914f6cdd1d
            result = (result << 11) ^ (result >> 5) ^ 0x369dea0f31a53f85
            result = (result << 13) ^ (result >> 7) ^ 0xdb4f0b9175ae2165
            result = (result << 17) ^ (result >> 9) ^ 0xbb67ae8584caa73b
            result = (result << 19) ^ (result >> 11) ^ 0x3c6ef372fe94f82b
            result = (result << 23) ^ (result >> 13) ^ 0xa54ff53a5f1d36f1
            result = (result << 29) ^ (result >> 17) ^ 0x510e527fade682d1
            result = (result << 31) ^ (result >> 19) ^ 0x1f83d9abfb41bd6b
            result = (result << 37) ^ (result >> 23) ^ 0x5be0cd19137e2179
            return result
        }

        #[Swag.NoInline]
        func edited(value: u64)->u64
        {
            var result = value ^ %
            result = (result << 7) ^ (result >> 3) ^ 0x243f6a8885a308d3
            result = (result << 5) ^ (result >> 11) ^ 0x13198a2e03707344
            result = (result << 9) ^ (result >> 13) ^ 0xa4093822299f31d0
            result = (result << 3) ^ (result >> 17) ^ 0x082efa98ec4e6c89
            result = (result << 11) ^ (result >> 5) ^ 0x452821e638d01377
            result = (result << 13) ^ (result >> 7) ^ 0xbe5466cf34e90c6c
            result = (result << 17) ^ (result >> 9) ^ 0xc0ac29b7c97c50dd
            result = (result << 19) ^ (result >> 11) ^ 0x3f84d5b5b5470917
            result = (result << 23) ^ (result >> 13) ^ 0x9216d5d98979fb1b
            result = (result << 29) ^ (result >> 17) ^ 0xd1310ba698dfb5ac
            result = (result << 31) ^ (result >> 19) ^ 0x2ffd72dbd01adfb7
            result = (result << 37) ^ (result >> 23) ^ 0xb8e1afed6a267e96
            return result
        }

        #main
        {
            if stable(1) != edited(2) do Swag.print("function-cache-value=%\n")
        }
        """, seed, marker)
}

// A source edit rebuilds the module, but an unchanged relocation-free leaf keeps its cached COFF
// member and skips the expensive micro passes and encoder.
private func verifyIncrementalFunctionCache(context: *Context, options: *Options, workspace, buildCfg: string)->s32 fail
{
    let scratch = Path.combine(workspace, ".tmp", "incremental-function-cache-probe")
    if Directory.exists(scratch) do
        try Directory.delete(scratch.toString(), recurse: true)
    defer discard catch Directory.delete(scratch.toString(), recurse: true)

    let modules         = Path.combine(scratch.toString(), "modules")
    let moduleDirectory = Path.combine(modules.toString(), "function_cache")
    let sourceDirectory = Path.combine(moduleDirectory.toString(), "src")
    try Directory.create(scratch.toString())
    try Directory.create(modules.toString())
    try Directory.create(moduleDirectory.toString())
    try Directory.create(sourceDirectory.toString())
    try File.writeAllText(Path.combine(moduleDirectory.toString(), "module.swg").toString(), "#run { Swag.compiler().getBuildCfg()!.backendKind = .Executable }\n")

    let sourcePath = Path.combine(sourceDirectory.toString(), "main.swg")
    try File.writeAllText(sourcePath.toString(), incrementalFunctionCacheSource(1, 1))

    var command = workspaceModuleCommand("run", scratch.toString(), "function_cache", buildCfg)
    command.add(["--incremental"])
    options.appendExtra(&command)

    let firstOutput = try context.captureCompiler(command)
    Console.print(firstOutput.toString())
    if not Utf8.contains(firstOutput.toString(), "function-cache-value=1")
    {
        Console.println("The initial incremental function-cache executable did not run")
        return 1
    }

    let cacheDirectory = Path.combine(scratch.toString(), ".tmp", "function_cache", "executable", buildCfg, options.targetArch.toString())
    let cacheArchive   = Path.combine(cacheDirectory.toString(), "function_cache.incremental.lib")
    let cacheIndex     = Path.combine(cacheDirectory.toString(), "function_cache.incremental.idx")
    if not File.exists(cacheArchive.toString()) or not File.exists(cacheIndex.toString())
    {
        Console.println("The initial incremental build did not publish its function cache")
        return 1
    }
    let originalArchive = try File.readAllBytes(cacheArchive.toString())
    let originalIndex   = try File.readAllBytes(cacheIndex.toString())

    try File.writeAllText(sourcePath.toString(), incrementalFunctionCacheSource(2, 2))
    let editedOutput = try context.captureCompiler(command)
    Console.print(editedOutput.toString())
    if not Utf8.contains(editedOutput.toString(), "function-cache-value=2") or not Utf8.contains(editedOutput.toString(), "reused function")
    {
        Console.println("A body edit did not reuse an unchanged function from the incremental cache")
        return 1
    }

    try File.writeAllText(sourcePath.toString(), incrementalFunctionCacheSource(1, 1))
    let restoredOutput = try context.captureCompiler(command)
    Console.print(restoredOutput.toString())
    let restoredArchive = try File.readAllBytes(cacheArchive.toString())
    let restoredIndex   = try File.readAllBytes(cacheIndex.toString())
    if not Utf8.contains(restoredOutput.toString(), "function-cache-value=1") or restoredArchive.toSlice() != originalArchive.toSlice() or restoredIndex.toSlice() != originalIndex.toSlice()
    {
        Console.println("Rebuilding identical functions did not reproduce the same incremental cache")
        return 1
    }

    var rebuild = workspaceModuleCommand("run", scratch.toString(), "function_cache", buildCfg)
    rebuild.add(["--rebuild"])
    options.appendExtra(&rebuild)
    let rebuiltOutput = try context.captureCompiler(rebuild)
    Console.print(rebuiltOutput.toString())
    if Utf8.contains(rebuiltOutput.toString(), "reused function")
    {
        Console.println("A rebuild reused the incremental function cache")
        return 1
    }

    return 0
}

// WriteFile publishes fresh native bytes and their completion marker without redating the API.
private func workspaceNativePublisher(sourceDirectory, destinationDirectory: string)->String
{
    return Format.toString(#raw """
        #global private
        public const Marker = 1
        #run
        {
            expect Core.File.duplicate(#raw "%/provider.dll", #raw "%/provider.dll")
            expect Core.File.duplicate(#raw "%/.swc-artifacts", #raw "%/.swc-artifacts")
        }
        """, destinationDirectory, sourceDirectory, destinationDirectory, sourceDirectory)
}

// Runs the multi-module workspace suite.
private func runWorkspaceSuite(context: *Context, options: *Options, buildCfg: string)->s32 fail
{
    let workspace = Path.combine(context.binDir.toString(), "unittests", "workspace")

    // A user workspace owns only its external imports. Start without generated artifacts so the
    // suite can distinguish newly materialized external dependencies from workspace-local output.
    var cleanedWorkspace: Arguments
    cleanedWorkspace.add(["clean", "--workspace", workspace.toString()])
    let cleanWorkspaceCode = try context.runCompiler(cleanedWorkspace)
    if cleanWorkspaceCode != 0 do
        return cleanWorkspaceCode

    // Start without prebuilt standard modules so this suite proves that the compiler resolves and
    // builds them, while leaving unrelated modules absent instead of preparing the whole workspace.
    var cleanedStd: Arguments
    cleanedStd.add(["clean", "--workspace", context.workspacePath("std").toString()])
    let cleanStdCode = try context.runCompiler(cleanedStd)
    if cleanStdCode != 0 do
        return cleanStdCode

    var built = workspaceModuleCommand("build", workspace.toString(), "consumer_exe", buildCfg)
    options.appendExtra(&built)

    // Hold a competing writer's staging file through artifact collection, then remove it.
    // Its disappearance must not invalidate the executable's completed publication.
    var stagedOutput = Path.combine(workspace.toString(), ".output")
    if not Directory.exists(stagedOutput.toString()) do
        try Directory.create(stagedOutput.toString())
    for part in ["consumer_exe", "executable", buildCfg, options.targetArch.toString()]
    {
        stagedOutput = Path.combine(stagedOutput.toString(), part)
        if not Directory.exists(stagedOutput.toString()) do
            try Directory.create(stagedOutput.toString())
    }

    let stagedArtifact = Path.combine(stagedOutput.toString(), "consumer_exe.exe.123.1.swctmp")
    try File.writeAllText(stagedArtifact.toString(), "incomplete competing publication")
    defer discard catch File.delete(stagedArtifact.toString())

    let buildOutput = try context.captureCompiler(built)
    Console.print(buildOutput.toString())
    for dependency in ["core", "win32", "xinput"] where moduleReportCount(buildOutput.toString(), dependency) != 1
    {
        Console.println("Workspace dependency plan did not compile standard module exactly once: ", dependency)
        return 1
    }

    let dependencyLayoutCode = verifyWorkspaceDependencyLayout(context, workspace.toString())
    if dependencyLayoutCode != 0 do
        return dependencyLayoutCode

    let compactApiCode = try verifyCompactExportedApi(workspace.toString(), buildCfg, options.targetArch.toString())
    if compactApiCode != 0 do
        return compactApiCode

    let artifactLayoutCode = try verifyWorkspaceArtifactLayout(workspace.toString(), buildCfg, options.targetArch.toString())
    if artifactLayoutCode != 0 do
        return artifactLayoutCode

    let stdOutput = context.workspaceOutput("std")
    if not Directory.exists(Path.combine(stdOutput.toString(), "core"))
    {
        Console.println("Workspace import did not build its standard dependency.")
        return 1
    }

    for unrelated in ["audio", "gdiplus", "gui"] where Directory.exists(Path.combine(stdOutput.toString(), unrelated))
    {
        Console.println("Workspace import built unrelated standard module \"", unrelated, "\".")
        return 1
    }

    try File.delete(stagedArtifact.toString())
    let warmBuildOutput = try context.captureCompiler(built)
    Console.print(warmBuildOutput.toString())
    if not artifactReportedUpToDate(warmBuildOutput.toString(), "consumer_exe.exe")
    {
        Console.println("Removing a competing publication's temporary file invalidated the workspace executable.")
        return 1
    }

    for dependency in ["core", "win32", "xinput"] where moduleReportCount(warmBuildOutput.toString(), dependency) != 0
    {
        Console.println("Reusable workspace dependency added noise to the build report: ", dependency)
        return 1
    }

    let setupCacheCode = try verifyModuleSetupCacheInvalidation(context, options, workspace.toString(), buildCfg)
    if setupCacheCode != 0 do
        return setupCacheCode

    let standaloneSetupCode = try verifyStandaloneModuleSetupCache(context, options, workspace.toString(), buildCfg)
    if standaloneSetupCode != 0 do
        return standaloneSetupCode

    let tagCacheCode = try verifyWorkspaceTagCache(context, options, workspace.toString(), buildCfg)
    if tagCacheCode != 0 do
        return tagCacheCode

    let debugVariantCode = try verifyWorkspaceDebugVariant(context, options, workspace.toString(), buildCfg)
    if debugVariantCode != 0 do
        return debugVariantCode

    let stackTraceCode = try verifyWorkspaceDependencyStackTrace(context, options, workspace.toString(), buildCfg)
    if stackTraceCode != 0 do
        return stackTraceCode

    let sourceEditCode = try verifyWorkspaceSourceEditDuringBuild(context, options, workspace.toString(), buildCfg)
    if sourceEditCode != 0 do
        return sourceEditCode
    let nativeReadCode = try verifyWorkspaceNativeReadDuringBuild(context, options, workspace.toString(), buildCfg)
    if nativeReadCode != 0 do
        return nativeReadCode

    let privateDependencyCode = try verifyPrivateDependencyInvalidation(context, options, workspace.toString(), buildCfg)
    if privateDependencyCode != 0 do
        return privateDependencyCode

    let incrementalFunctionCacheCode = try verifyIncrementalFunctionCache(context, options, workspace.toString(), buildCfg)
    if incrementalFunctionCacheCode != 0 do
        return incrementalFunctionCacheCode

    // Documentation consumes local native artifacts for compile-time execution, but does not
    // produce those artifacts itself. Starting it from a clean workspace proves that its publish
    // pass fills '.output' without using '.dep' as a snapshot of local modules.
    let cleanBeforeDocCode = try context.runCompiler(cleanedWorkspace)
    if cleanBeforeDocCode != 0 do
        return cleanBeforeDocCode

    var documented = workspaceModuleCommand("doc", workspace.toString(), "consumer_exe", buildCfg)
    documented.add(["--doc-output-dir", Path.combine(workspace.toString(), ".output", "docs").toString(), "--rebuild"])
    options.appendExtra(&documented)

    let docCode = try context.runCompiler(documented)
    if docCode != 0 do
        return docCode

    if not File.exists(Path.combine(workspace.toString(), ".output", "docs", "workspace.consumer.html"))
    {
        Console.println("Workspace documentation did not produce 'workspace.consumer.html'.")
        return 1
    }

    let documentedDependencyLayoutCode = verifyWorkspaceDependencyLayout(context, workspace.toString())
    if documentedDependencyLayoutCode != 0 do
        return documentedDependencyLayoutCode

    // A forced standard-library rebuild loads the new DLLs while the test command is still
    // compiling. Their one-time initialization must already see the sandbox arguments that the
    // ensuing JIT test run inherits.
    var sandboxed = workspaceModuleCommand("test", workspace.toString(), "sandbox_consumer", buildCfg)
    sandboxed.add(["--rebuild", "--no-test-native"])
    options.appendExtra(&sandboxed)

    let sandboxCode = try context.runCompiler(sandboxed)
    if sandboxCode != 0 do
        return sandboxCode

    // The forced standard-library rebuild deliberately invalidates the executable built above.
    // Refresh that normal artifact before checking that test-mode publications leave it reusable.
    let refreshedBuildCode = try context.runCompiler(built)
    if refreshedBuildCode != 0 do
        return refreshedBuildCode

    var dynamicLibraryBuild = workspaceModuleCommand("build", workspace.toString(), "runtime_context_dynamic_dll", buildCfg)
    options.appendExtra(&dynamicLibraryBuild)

    let dynamicLibraryBuildCode = try context.runCompiler(dynamicLibraryBuild)
    if dynamicLibraryBuildCode != 0 do
        return dynamicLibraryBuildCode

    let dynamicLibrary  = Path.combine(workspace.toString(), ".output", "runtime_context_dynamic_dll", "shared-library", buildCfg, options.targetArch.toString(), "runtime_context_dynamic_dll.dll")
    var dynamicConsumer = workspaceModuleCommand("test", workspace.toString(), "runtime_context_dynamic_consumer", buildCfg)
    dynamicConsumer.add(["--no-test-jit", "--run-arg", Format.toString("--dynamic-runtime-library=%", dynamicLibrary.toString()).toString()])
    options.appendExtra(&dynamicConsumer)

    let dynamicConsumerCode = try context.runCompiler(dynamicConsumer)
    if dynamicConsumerCode != 0 do
        return dynamicConsumerCode

    var tested = workspaceModuleCommand("test", workspace.toString(), "consumer_exe", buildCfg)
    tested.add(["--no-test-jit"])
    options.appendExtra(&tested)

    let testCode = try context.runCompiler(tested)
    if testCode != 0 do
        return testCode

    let testArtifactLayoutCode = try verifyWorkspaceTestArtifactLayout(workspace.toString(), buildCfg, options.targetArch.toString(), false)
    if testArtifactLayoutCode != 0 do
        return testArtifactLayoutCode

    // An unchanged native-only test must reuse its compiled artifact but still execute it.
    let reusedOutput = try context.captureCompiler(tested)
    Console.print(reusedOutput.toString())
    if not artifactReportedUpToDate(reusedOutput.toString(), "consumer_exe.test.exe")
    {
        Console.println("Workspace test recompiled its unchanged test artifact.")
        return 1
    }

    if not reusedOutput.contains("SWAG_WORKSPACE_TEST_RAN")
    {
        Console.println("Workspace test did not execute its reused #test function.")
        return 1
    }

    // An executable that names no link kind takes its dependencies' code in and ships alone. Its
    // own tests check both halves of that: a call across what was a module boundary, and the
    // absence of any shared library beside the artifact.
    var standalone = workspaceModuleCommand("test", workspace.toString(), "standalone_exe", buildCfg)
    standalone.add(["--no-test-jit"])
    options.appendExtra(&standalone)

    let standaloneCode = try context.runCompiler(standalone)
    if standaloneCode != 0 do
        return standaloneCode

    var verified = workspaceModuleCommand("test", workspace.toString(), "verify_expectations", buildCfg)
    verified.add(["--no-test-jit"])
    options.appendExtra(&verified)

    let verifyCode = try context.runCompiler(verified)
    if verifyCode != 0 do
        return verifyCode

    // Only the module carrying the directives must recompile; a dependency of its own is free to
    // be reused, and naming the module keeps that from reading as the failure.
    let verifiedAgain = try context.captureCompiler(verified)
    Console.print(verifiedAgain.toString())
    if verifiedAgain.contains("std [core]")
    {
        Console.println("Workspace modules rebuilt a shared standard dependency.")
        return 1
    }

    if not testPhaseCompiled(verifiedAgain.toString(), "verify_expectations")
    {
        Console.println("Workspace test reused a module with source-driven Verify directives.")
        return 1
    }

    var ran = workspaceModuleCommand("run", workspace.toString(), "consumer_exe", buildCfg)
    options.appendExtra(&ran)

    let output = try context.captureCompiler(ran)
    Console.print(output.toString())

    if not output.contains("SWAG_WORKSPACE_MAIN_RAN")
    {
        Console.println("Workspace run did not reach the normal entry point after a test build.")
        return 1
    }

    if not artifactReportedUpToDate(output.toString(), "consumer_exe.exe")
    {
        Console.println("Workspace run recompiled its unchanged executable after a test build.")
        return 1
    }

    let reusedAfterRun = try context.captureCompiler(tested)
    Console.print(reusedAfterRun.toString())
    if not artifactReportedUpToDate(reusedAfterRun.toString(), "consumer_exe.test.exe")
    {
        Console.println("Workspace test recompiled its unchanged test artifact after a normal run.")
        return 1
    }

    var focused = workspaceModuleCommand("test", workspace.toString(), "consumer_exe", buildCfg)
    focused.add(["--no-test-jit", "--test-file", "portable_memory.test.swg"])
    options.appendExtra(&focused)

    let focusedCode = try context.runCompiler(focused)
    if focusedCode != 0 do
        return focusedCode

    let focusedArtifactLayoutCode = try verifyWorkspaceTestArtifactLayout(workspace.toString(), buildCfg, options.targetArch.toString(), true)
    if focusedArtifactLayoutCode != 0 do
        return focusedArtifactLayoutCode

    // The script's marker is data the suite reads, not a line for the person watching, so its
    // output is captured and only a run that failed to reach the entry point has anything to show.
    var script: Arguments
    script.add(["--build-cfg", buildCfg])
    options.appendExtra(&script)
    script.add([Path.combine(workspace.toString(), "import_core_without_using.swgs").toString()])

    let scripted = try context.captureCompiler(script)
    if not scripted.contains("SWAG_IMPORTED_CORE_WITHOUT_USING_RAN")
    {
        Console.println("Script importing 'core' without a 'using' did not reach its entry point.")
        return 1
    }

    return 0
}
