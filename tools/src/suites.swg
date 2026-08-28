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
        if !options.devMode do
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
        return try runSourceSuite(context, options, "unittests/native", "Native", "executable", "", buildCfg)

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
    if @countof(stage) != 0 do
        arguments.add([stage])

    options.appendExtra(&arguments)
    return try context.runCompiler(arguments)
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
        if Utf8.contains(line, module) and Utf8.contains(line, "tests") and !Utf8.contains(line, "up-to-date") do
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
    for dependency in ["core", "win32", "xinput"] where !Directory.exists(Path.combine(dependencyDirectory.toString(), dependency))
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
        if !generated.contains(redundant) and !wholeFile.contains(redundant) do
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

    if !wholeFile.contains("#[Discardable, Inline]")
    {
        Console.println("Whole-file module API is missing compact attribute list: #[Discardable, Inline]")
        return 1
    }

    for redundant in ["#[Opaque]", "Opaque]", "Pack(8)", "NoDoc", "NoDuplicate"]
    {
        if !generated.contains(redundant) and !staticApi.contains(redundant) do
            continue

        Console.println("Generated module API still contains a producer-only attribute: ", redundant)
        return 1
    }

    if !staticApi.contains("#[Foreign, Discardable]") or !staticApi.contains("func depTriple(value: s32)->s32")
    {
        Console.println("Bodyless module API declaration lost a consumer attribute")
        return 1
    }

    let retainedBodyAttributes = "#[NoInline, Safety(.All, false), Sanity(.All, false), Optimize(false), Warning(\"all\", .Disable)]"
    if !staticApi.contains(retainedBodyAttributes) or !staticApi.contains("func(T) depMirror(value: T)->T => value")
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
        let name = Path.fileName(outputSource.fullname.toString()) orelse ""
        if Utf8.contains(name, ".gen.") or Utf8.contains(name, "-generated-source-")
        {
            Console.println("Non-debug workspace executable published generated source in '.output': ", name)
            return 1
        }
    }

    let intermediateDirectory = Path.combine(workspace, ".tmp", "consumer_exe", "executable", buildCfg, targetArch)
    var foundGeneratedSource: bool
    let generatedSources = try Directory.enumerateFiles(intermediateDirectory.toString(), ".swgsrc")
    for generatedSource in generatedSources
    {
        let name = Path.fileName(generatedSource.fullname.toString()) orelse ""
        if Utf8.contains(name, ".gen.") do
            foundGeneratedSource = true
        if Utf8.contains(name, "-generated-source-")
        {
            Console.println("Workspace intermediate directory retained the old generated-source file name: ", name)
            return 1
        }
    }

    if !foundGeneratedSource
    {
        Console.println("Non-debug workspace executable did not write '<module>.gen.<number>.swgsrc' in '.tmp'.")
        return 1
    }

    let staticDirectory = Path.combine(workspace, ".output", "api_static_provider", "static-library", buildCfg, targetArch)
    if !File.exists(Path.combine(staticDirectory.toString(), ".swc-deps"))
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
        let name = Path.fileName(outputFile.fullname.toString()) orelse ""
        if Utf8.contains(name, ".test.dll") or Utf8.contains(name, ".test.lib")
        {
            Console.println("Workspace test published a library artifact: ", outputFile.fullname.toString())
            return 1
        }

        if name == ".swc-artifacts.test"
        {
            let fullname = outputFile.fullname.toString()
            if !Utf8.contains(fullname, "/test/") and !Utf8.contains(fullname, "\\test\\")
            {
                Console.println("Non-executable workspace test published an artifact manifest: ", outputFile.fullname.toString())
                return 1
            }
        }

        if focused and Utf8.contains(name, ".focused")
        {
            Console.println("Focused workspace test published an artifact in '.output': ", outputFile.fullname.toString())
            return 1
        }
    }

    let testDirectory = Path.combine(workspace, ".output", "consumer_exe", "test", buildCfg, targetArch)
    if !File.exists(Path.combine(testDirectory.toString(), "consumer_exe.test.exe")) or
       !File.exists(Path.combine(testDirectory.toString(), ".swc-artifacts.test"))
    {
        Console.println("Reusable workspace test executable or its manifest is missing.")
        return 1
    }

    if focused
    {
        let focusedExecutable = Path.combine(workspace, ".tmp", "consumer_exe", "test", buildCfg, targetArch, "consumer_exe.test.focused.exe")
        if !File.exists(focusedExecutable)
        {
            Console.println("Focused workspace test executable is missing from '.tmp'.")
            return 1
        }
    }

    return 0
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
    if !Directory.exists(Path.combine(stdOutput.toString(), "core"))
    {
        Console.println("Workspace import did not build its standard dependency.")
        return 1
    }

    for unrelated in ["audio", "gdiplus", "gui"] where Directory.exists(Path.combine(stdOutput.toString(), unrelated))
    {
        Console.println("Workspace import built unrelated standard module \"", unrelated, "\".")
        return 1
    }

    let warmBuildOutput = try context.captureCompiler(built)
    Console.print(warmBuildOutput.toString())
    for dependency in ["core", "win32", "xinput"] where moduleReportCount(warmBuildOutput.toString(), dependency) != 0
    {
        Console.println("Reusable workspace dependency added noise to the build report: ", dependency)
        return 1
    }

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

    if !File.exists(Path.combine(workspace.toString(), ".output", "docs", "workspace.consumer.html"))
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
    if !reusedOutput.contains("up-to-date • consumer_exe.test.exe")
    {
        Console.println("Workspace test recompiled its unchanged test artifact.")
        return 1
    }

    if !reusedOutput.contains("SWAG_WORKSPACE_TEST_RAN")
    {
        Console.println("Workspace test did not execute its reused #test function.")
        return 1
    }

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

    if !testPhaseCompiled(verifiedAgain.toString(), "verify_expectations")
    {
        Console.println("Workspace test reused a module with source-driven Verify directives.")
        return 1
    }

    var ran = workspaceModuleCommand("run", workspace.toString(), "consumer_exe", buildCfg)
    options.appendExtra(&ran)

    let output = try context.captureCompiler(ran)
    Console.print(output.toString())

    if !output.contains("SWAG_WORKSPACE_MAIN_RAN")
    {
        Console.println("Workspace run did not reach the normal entry point after a test build.")
        return 1
    }

    if !output.contains("up-to-date • consumer_exe.exe")
    {
        Console.println("Workspace run recompiled its unchanged executable after a test build.")
        return 1
    }

    let reusedAfterRun = try context.captureCompiler(tested)
    Console.print(reusedAfterRun.toString())
    if !reusedAfterRun.contains("up-to-date • consumer_exe.test.exe")
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
    if !scripted.contains("SWAG_IMPORTED_CORE_WITHOUT_USING_RAN")
    {
        // A capture drops what the compiler wrote to its error stream, which is exactly what a
        // failure needs to say, so the run is repeated in the open before the suite reports.
        discard try context.runCompiler(script)
        Console.println("Script importing 'core' without a 'using' did not reach its entry point.")
        return 1
    }

    return 0
}
