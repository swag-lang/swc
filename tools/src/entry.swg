#global namespace Tool

using Core

// Runs the tool `name`, reading its command line from the arguments the compiler handed over.
//
// `loc` is the script that called this, which is how a tool finds the repository: it sits in
// `<root>/tools/`, so its own path names the root without anything having to be configured,
// exported, or passed in. That is what lets a tool be double-clicked, launched from any
// directory, and copied to a checkout somewhere else with no setup at all.
public func launch(name: string, loc = #callerlocation)->s32
{
    let script = loc.fileName orelse ""
    if @countof(script) == 0
    {
        Console.println("error: the tool cannot locate itself")
        return 1
    }

    let toolsDir = Path.directoryName(script) orelse ""
    let root     = Path.directoryName(toolsDir) orelse ""

    let code = catch dispatch(name, root, scriptArguments()) as err
    if err != null
    {
        Console.println("error: ", Errors.message(err))
        return 1
    }

    return code
}

// Returns the arguments meant for the tool.
//
// Element zero is the compiler that ran the script, which is not part of what the tool was
// asked to do. The slice is borrowed from the runtime and stays valid for the whole process.
private func scriptArguments()->const [..] string
{
    let args = Env.arguments()
    if @countof(args) == 0 do
        return args
    return args[1 until @countof(args)]
}

// Runs the tool `name` against `root` and returns the exit code it produced.
private func dispatch(name: string, root: string, tokens: const [..] string)->s32 fail
{
    let accepted = acceptedCommands(name)

    var options = try parseOptions(accepted.toSlice(), tokens)
    if options.wantHelp do
        return printUsage(name)

    var context = try Context.create(root, options)

    switch name
    {
    case "std":
        if options.command.isEmpty() do
            options.command = String.from("build")
        return try runStd(&context, &options)

    case "examples":
        return try runExamples(&context, &options)

    case "apps":
        return try runApps(&context, &options)

    case "reference":
        if options.command.isEmpty() do
            options.command = String.from("test")
        return try runReference(&context, &options)

    case "scripts":
        return try runScripts(&context, &options)

    case "unittests":
        return try runUnittests(&context, &options)

    case "tests":
        return try runTests(&context, &options)

    case "build":
        return try runBuild(&context, &options)

    case "format":
        return try runFormat(&context, &options)

    case "goldens":
        return try runGoldens(&context, &options)

    case "web":
        return try runWeb(&context, &options)

    case "scrypt":
        return try runScrypt(&context, &options)

    case "vsix":
        return try runVsix(&context, &options)

    case "setup":
        return try runSetup(&context, &options)

    case "bench":
        return try runBench(&context, &options)
    }

    Console.println("error: '", name, "' is not a repository tool")
    return 1
}

// Returns the commands one tool accepts as its first positional.
//
// Which words are commands is part of the grammar: a first positional the tool has no command
// for is read as the module, suite, or script name instead.
private func acceptedCommands(name: string)->Array'(string)
{
    var result: retval

    switch name
    {
    case "std", "reference":
        result.add("build")
        result.add("test")

    case "examples", "apps":
        result.add("build")
        result.add("run")
        result.add("test")
        result.add("smoke")

    case "scripts":
        result.add("run")
        result.add("smoke")

    case "tests":
        result.add("changed")
        result.add("plan")
    }

    return result
}
