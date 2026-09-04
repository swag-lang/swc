#global namespace Tool

using Core

/*
The complete repository test set.

The set is a ladder of five rungs, ordered by what each one costs against what it can see, and
every rung runs in every requested configuration before the next one starts. A defect that only
release can produce then reports in the first minute instead of after two complete passes: the
configuration is the inner loop, not the outer one.
*/
public func runTests(context: *Context, options: *Options)->s32 fail
{
    let portability = try auditPortability(context)
    if portability != 0 do
        return portability

    let backlog = try auditBacklog(context)
    if backlog != 0 do
        return backlog

    let notices = try auditNotices(context)
    if notices != 0 do
        return notices

    if !options.module.isEmpty()
    {
        Console.println("tests.swgs runs a whole set and takes no name. Use unittests, std, examples, apps,")
        Console.println("reference, or scripts to reach one suite, module, or script.")
        return 1
    }

    return try runWholeSet(context, options)
}

// Builds every repository workspace.
public func runBuild(context: *Context, options: *Options)->s32 fail
{
    if !options.module.isEmpty()
    {
        Console.println("build.swgs builds every workspace and takes no name. Use std, examples, apps, or")
        Console.println("reference to build one workspace or one module.")
        return 1
    }

    for cfg in options.configurations()
    {
        var sub = forConfiguration(options, cfg.toString())
        sub.command = String.from("build")

        let steps = try buildEveryWorkspace(context, &sub)
        if steps != 0 do
            return steps
    }

    return 0
}

private func buildEveryWorkspace(context: *Context, options: *Options)->s32 fail
{
    let library = try runStd(context, options)
    if library != 0 do
        return library

    let examples = try runExamples(context, options)
    if examples != 0 do
        return examples

    let apps = try runApps(context, options)
    if apps != 0 do
        return apps

    let reference = try runReference(context, options)
    if reference != 0 do
        return reference

    var arguments: Arguments
    arguments.add(["build", "--workspace", Path.combine(context.binDir.toString(), "unittests", "workspace").toString()])
    arguments.add(["--build-cfg", options.buildCfg.toString()])
    options.appendExtra(&arguments)
    return try context.runCompiler(arguments)
}

// Returns a copy of `options` bound to one configuration.
public func forConfiguration(options: *Options, buildCfg: string)->Options
{
    var result = options[]
    result.buildCfg   = String.from(buildCfg)
    result.allConfigs = false
    return result
}

private func runWholeSet(context: *Context, options: *Options)->s32 fail
{
    let configurations = options.configurations()

    // Rung 1. The frontend, and the compiler's own C++ suite: nothing here reaches a backend,
    // and between them they answer in seconds.
    for cfg in configurations
    {
        var sub = forConfiguration(options, cfg.toString())
        for suite in frontendSuites()
        {
            let code = try runSuite(context, &sub, suite, cfg.toString())
            if code != 0 do
                return code
        }
    }

    // Rung 2. Generated code, still on sources that stand alone. This is where a miscompile dies.
    for cfg in configurations
    {
        var sub = forConfiguration(options, cfg.toString())
        for suite in codegenSuites()
        {
            let code = try runSuite(context, &sub, suite, cfg.toString())
            if code != 0 do
                return code
        }
    }

    // Rung 3. The standard library against its own assertions.
    for cfg in configurations
    {
        var sub = forConfiguration(options, cfg.toString())
        sub.command = String.from("test")
        let code = try runStd(context, &sub)
        if code != 0 do
            return code
    }

    // Rung 4. What is shipped, and what documents the language.
    for cfg in configurations
    {
        var sub = forConfiguration(options, cfg.toString())
        sub.command = String.from("test")
        let apps = try runApps(context, &sub)
        if apps != 0 do
            return apps

        var reference = forConfiguration(options, cfg.toString())
        reference.command = String.from("test")
        let referenced = try runReference(context, &reference)
        if referenced != 0 do
            return referenced
    }

    // Rung 5. Programs that only prove they start. Most of the campaign's time lives here, and
    // none of it can report anything an assertion above has not already had the chance to catch.
    for cfg in configurations
    {
        var scripts = forConfiguration(options, cfg.toString())
        scripts.command = String.from("smoke")
        scripts.module.clear()
        let scripted = try runScripts(context, &scripts)
        if scripted != 0 do
            return scripted

        var examples = forConfiguration(options, cfg.toString())
        examples.command = String.from("smoke")
        examples.module.clear()
        let exampled = try runExamples(context, &examples)
        if exampled != 0 do
            return exampled

        var apps = forConfiguration(options, cfg.toString())
        apps.command = String.from("smoke")
        apps.module.clear()
        let smoked = try runApps(context, &apps)
        if smoked != 0 do
            return smoked
    }

    return 0
}
