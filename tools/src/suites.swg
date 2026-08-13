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

// Runs the multi-module workspace suite.
//
// A test build writes a different executable to the normal output path, so the run that follows
// has to rebuild the one holding the regular `#main`; the marker it prints is what proves the
// rebuild happened rather than the test artifact being launched again.
private func runWorkspaceSuite(context: *Context, options: *Options, buildCfg: string)->s32 fail
{
    let workspace = Path.combine(context.binDir.toString(), "unittests", "workspace")

    // A user workspace owns only its imports. Start without prebuilt standard modules so this
    // suite proves that the compiler resolves and builds them, while leaving unrelated modules
    // absent instead of preparing the whole standard workspace.
    var cleaned: Arguments
    cleaned.add(["clean", "--workspace", context.workspacePath("std").toString()])
    let cleanCode = try context.runCompiler(cleaned)
    if cleanCode != 0 do
        return cleanCode

    var built = workspaceModuleCommand("build", workspace.toString(), "consumer_exe", buildCfg)
    options.appendExtra(&built)

    let buildCode = try context.runCompiler(built)
    if buildCode != 0 do
        return buildCode

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

    // A forced standard-library rebuild loads the new DLLs while the test command is still
    // compiling. Their one-time initialization must already see the sandbox arguments that the
    // ensuing JIT test run inherits.
    var sandboxed = workspaceModuleCommand("test", workspace.toString(), "sandbox_consumer", buildCfg)
    sandboxed.add(["--rebuild", "--no-test-native"])
    options.appendExtra(&sandboxed)

    let sandboxCode = try context.runCompiler(sandboxed)
    if sandboxCode != 0 do
        return sandboxCode

    var tested = workspaceModuleCommand("test", workspace.toString(), "consumer_exe", buildCfg)
    tested.add(["--no-test-jit"])
    options.appendExtra(&tested)

    let testCode = try context.runCompiler(tested)
    if testCode != 0 do
        return testCode

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

    if verifiedAgain.contains("verify_expectations • up-to-date")
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
