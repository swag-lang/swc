#global namespace Tool

using Core

/*
The repository test set, whole or scoped to what changed.

The set is a ladder of five rungs, ordered by what each one costs against what it can see, and
every rung runs in every requested configuration before the next one starts. A defect that only
release can produce then reports in the first minute instead of after two complete passes: the
configuration is the inner loop, not the outer one.

`changed` asks the scope map which surfaces the working tree touches and climbs the same ladder
carrying only their work. It never writes to a tracked file: the two commands that are validated
by regenerating their output, doc and format, are reported as steps to take.
*/
public func runTests(context: *Context, options: *Options)->s32 fail
{
    let portability = try auditPortability(context)
    if portability != 0 do
        return portability

    let backlog = try auditBacklog(context)
    if backlog != 0 do
        return backlog

    if !options.module.isEmpty() and options.command.isEmpty()
    {
        Console.println("tests.swgs runs a whole set and takes no name. Use unittests, std, examples, apps,")
        Console.println("reference, or scripts to reach one suite, module, or script.")
        return 1
    }

    if options.command.isEmpty() do
        return try runWholeSet(context, options)

    var named: Array'String
    if !options.module.isEmpty() do
        named.add(options.module)

    var scope = try resolveScope(context, named.toSlice())
    reportScope(context, options, &scope)

    if options.command == "plan" do
        return 0
    if scope.count == 0 do
        return 0
    if scope.all do
        return try runWholeSet(context, options)

    return try runScopedSet(context, options, &scope)
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
    var result = dref options
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

private func runScopedSet(context: *Context, options: *Options, scope: *Scope)->s32 fail
{
    let configurations = options.configurations()

    for cfg in configurations
    {
        var sub = forConfiguration(options, cfg.toString())
        for suite in frontendSuites()
        {
            if !scope.suites.contains(String.from(suite)) do
                continue
            let code = try runSuite(context, &sub, suite, cfg.toString())
            if code != 0 do
                return code
        }
    }

    for cfg in configurations
    {
        var sub = forConfiguration(options, cfg.toString())
        for suite in codegenSuites()
        {
            if !scope.suites.contains(String.from(suite)) do
                continue
            let code = try runSuite(context, &sub, suite, cfg.toString())
            if code != 0 do
                return code
        }
    }

    // A whole family goes through its workspace in one invocation, which checks that workspace
    // once instead of once per name. Naming them one at a time is only worth it below that.
    for cfg in configurations
    {
        let code = try runSelectedModules(context, options, cfg.toString(), "std", "test", &scope.std)
        if code != 0 do
            return code
    }

    for cfg in configurations
    {
        let code = try runSelectedModules(context, options, cfg.toString(), "apps", "test", &scope.apps)
        if code != 0 do
            return code

        if scope.reference
        {
            var reference = forConfiguration(options, cfg.toString())
            reference.command = String.from("test")
            let referenced = try runReference(context, &reference)
            if referenced != 0 do
                return referenced
        }
    }

    for cfg in configurations
    {
        let scripted = try runSelectedScripts(context, options, cfg.toString(), scope)
        if scripted != 0 do
            return scripted

        let exampled = try runSelectedModules(context, options, cfg.toString(), "examples", "smoke", &scope.examples)
        if exampled != 0 do
            return exampled

        let smoked = try runSelectedModules(context, options, cfg.toString(), "apps", "smoke", &scope.apps)
        if smoked != 0 do
            return smoked
    }

    return 0
}

private func runSelectedModules(context: *Context, options: *Options, cfg: string, workspace: string, command: string, selected: *HashSet'String)->s32 fail
{
    let names = context.workspaceModules(workspace)
    var count = 0'u64
    for name in names
    {
        if selected.contains(name) do
            count += 1
    }

    if count == 0 do
        return 0

    var sub = forConfiguration(options, cfg)
    sub.command = String.from(command)

    // The whole family in one invocation once everything is selected.
    if count == names.count
    {
        sub.module.clear()
        return try runWorkspaceCommand(context, &sub, workspace)
    }

    for name in names
    {
        if !selected.contains(name) do
            continue
        sub.module = name
        let code = try runWorkspaceCommand(context, &sub, workspace)
        if code != 0 do
            return code
    }

    return 0
}

private func runWorkspaceCommand(context: *Context, options: *Options, workspace: string)->s32 fail
{
    switch workspace
    {
    case "std":      return try runStd(context, options)
    case "examples": return try runExamples(context, options)
    case "apps":     return try runApps(context, options)
    }

    return 0
}

private func runSelectedScripts(context: *Context, options: *Options, cfg: string, scope: *Scope)->s32 fail
{
    let scriptsDir = Path.combine(context.workspacePath("examples").toString(), "scripts")
    let entries    = catch Directory.enumerateFiles(scriptsDir.toString(), ".swgs") as err
    if err != null do
        return 0

    var names: Array'String
    for entry in entries do
        names.add(String.from(Path.fileNameWithoutExtension(entry.fullname.toString()) orelse ""))

    var count = 0'u64
    for name in names
    {
        if scope.scripts.contains(name) do
            count += 1
    }

    if count == 0 do
        return 0

    var sub = forConfiguration(options, cfg)
    sub.command = String.from("smoke")

    if count == names.count
    {
        sub.module.clear()
        return try runScripts(context, &sub)
    }

    for name in names
    {
        if !scope.scripts.contains(name) do
            continue
        sub.module = name
        let code = try runScripts(context, &sub)
        if code != 0 do
            return code
    }

    return 0
}

// Prints what the selection holds, in the shape the campaign reads it.
private func reportScope(context: *Context, options: *Options, scope: *Scope)
{
    if scope.count == 0
    {
        Console.println("Nothing changed against HEAD, so there is nothing to run.")
        return
    }

    Console.println(scope.count, " changed file(s) select:")
    var reported = false

    if scope.all
    {
        var configurations: String
        for cfg in options.configurations()
        {
            if @index != 0 do
                configurations += " "
            configurations += cfg
        }

        reportLine("everything", Format.toString("in %", configurations.toString()).toString(), &reported)
        if !scope.unknown.isEmpty() do
            reportLine("because", Format.toString("% matches no known surface", scope.unknown.toString()).toString(), &reported)
    }
    else
    {
        var suites: String
        for suite in allSuites()
        {
            if !scope.suites.contains(String.from(suite)) do
                continue
            if !suites.isEmpty() do
                suites += " "
            suites += suite
        }

        reportLine("suites", suites.toString(), &reported)
        reportNames(context, "std", "std", &scope.std, &reported)
        reportNames(context, "apps", "apps", &scope.apps, &reported)
        reportNames(context, "examples", "examples", &scope.examples, &reported)
        reportScripts(context, scope, &reported)
        if scope.reference do
            reportLine("reference", "the whole workspace", &reported)
    }

    // Both rewrite tracked files, so neither belongs inside a test command. They are named here
    // because the change that selected them is validated by reading what they produce.
    if scope.doc do
        reportLine("also", "regenerate with 'swc tools/web.swgs' and read the diff", &reported)
    if scope.format do
        reportLine("also", "reformat with 'swc tools/format.swgs' and read the diff", &reported)
    if !scope.warnProject.isEmpty() do
        reportLine("note", Format.toString("% may carry a compile flag; run the whole set by hand if it does", scope.warnProject.toString()).toString(), &reported)
    if !reported do
        reportLine("nothing", "no surface this campaign covers is affected", &reported)

    Console.println()
}

// Naming a handful says more than counting them; naming twenty says less.
private func reportNames(context: *Context, label: string, workspace: string, selected: *HashSet'String, reported: *bool)
{
    let names = context.workspaceModules(workspace)

    var count = 0'u64
    for name in names
    {
        if selected.contains(name) do
            count += 1
    }

    if count == 0 do
        return

    if count > 6
    {
        reportLine(label, Format.toString("% of %", count, names.count).toString(), reported)
        return
    }

    var line: String
    for name in names
    {
        if !selected.contains(name) do
            continue
        if !line.isEmpty() do
            line += " "
        line += name
    }

    reportLine(label, line.toString(), reported)
}

private func reportScripts(context: *Context, scope: *Scope, reported: *bool)
{
    let scriptsDir = Path.combine(context.workspacePath("examples").toString(), "scripts")
    let entries    = catch Directory.enumerateFiles(scriptsDir.toString(), ".swgs") as err
    if err != null do
        return

    var names: Array'String
    for entry in entries do
        names.add(String.from(Path.fileNameWithoutExtension(entry.fullname.toString()) orelse ""))

    var count = 0'u64
    for name in names
    {
        if scope.scripts.contains(name) do
            count += 1
    }

    if count == 0 do
        return

    if count > 6
    {
        reportLine("scripts", Format.toString("% of %", count, names.count).toString(), reported)
        return
    }

    var line: String
    for name in names
    {
        if !scope.scripts.contains(name) do
            continue
        if !line.isEmpty() do
            line += " "
        line += name
    }

    reportLine("scripts", line.toString(), reported)
}

private func reportLine(label: string, value: string, reported: *bool)
{
    if @countof(value) == 0 do
        return

    var padded = String.from(label)
    while padded.length < 10 do
        padded += " "

    Console.println("  ", padded.toString(), " ", value)
    dref reported = true
}
