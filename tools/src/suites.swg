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

    @print("Unknown suite \"", options.module.toString(), "\". Available suites:")
    for suite in allSuites() do
        @print(" ", suite)
    @print("\n")
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
        var arguments: Array'String
        arguments.add(String.from("unittest"))
        arguments.add(String.from("--dev-full"))
        options.appendExtra(&arguments)
        return try context.runCompiler(arguments.toSlice())

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

    var arguments: Array'String
    arguments.add(String.from("test"))
    arguments.add(String.from("--artifact-kind"))
    arguments.add(String.from("executable"))
    arguments.add(String.from("-d"))
    arguments.add(Path.combine(context.binDir.toString(), relative))
    arguments.add(String.from("--module-namespace"))
    arguments.add(String.from(moduleNamespace))
    arguments.add(String.from("--out-dir"))
    arguments.add(paths.outDir)
    arguments.add(String.from("--work-dir"))
    arguments.add(paths.workDir)
    arguments.add(String.from("--build-cfg"))
    arguments.add(String.from(buildCfg))
    if @countof(stage) != 0 do
        arguments.add(String.from(stage))

    options.appendExtra(&arguments)
    return try context.runCompiler(arguments.toSlice())
}

// Runs the multi-module workspace suite.
//
// A test build writes a different executable to the normal output path, so the run that follows
// has to rebuild the one holding the regular `#main`; the marker it prints is what proves the
// rebuild happened rather than the test artifact being launched again.
private func runWorkspaceSuite(context: *Context, options: *Options, buildCfg: string)->s32 fail
{
    let workspace = Path.combine(context.binDir.toString(), "unittests", "workspace")

    var built: Array'String
    built.add(String.from("build"))
    built.add(String.from("--workspace"))
    built.add(workspace)
    built.add(String.from("--workspace-module"))
    built.add(String.from("consumer_exe"))
    built.add(String.from("--build-cfg"))
    built.add(String.from(buildCfg))
    options.appendExtra(&built)

    let buildCode = try context.runCompiler(built.toSlice())
    if buildCode != 0 do
        return buildCode

    var tested: Array'String
    tested.add(String.from("test"))
    tested.add(String.from("--workspace"))
    tested.add(workspace)
    tested.add(String.from("--workspace-module"))
    tested.add(String.from("consumer_exe"))
    tested.add(String.from("--build-cfg"))
    tested.add(String.from(buildCfg))
    tested.add(String.from("--no-test-jit"))
    options.appendExtra(&tested)

    let testCode = try context.runCompiler(tested.toSlice())
    if testCode != 0 do
        return testCode

    var ran: Array'String
    ran.add(String.from("run"))
    ran.add(String.from("--workspace"))
    ran.add(workspace)
    ran.add(String.from("--workspace-module"))
    ran.add(String.from("consumer_exe"))
    ran.add(String.from("--build-cfg"))
    ran.add(String.from(buildCfg))
    options.appendExtra(&ran)

    let output = try context.captureProgram(context.compiler.toString(), ran.toSlice())
    @print(output.toString())

    if !output.contains("SWAG_WORKSPACE_MAIN_RAN")
    {
        @print("Workspace run did not reach the normal entry point after a test build.\n")
        return 1
    }

    return 0
}
