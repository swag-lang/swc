#global namespace Tool

using Core

/*
The argument grammar every repository tool shares.

    tool [dm] [<command>] [<name>] [options...]

Positionals come first and options after, so an option value can never be mistaken for a name:
the first token starting with `-` closes the positional part. The named options are parsed by
Core's command-line system through [Grammar]; anything the grammar does not know is forwarded
to the compiler untouched, which is what lets a caller pass `--seed` or `--num-cores` through
any tool.
*/
public struct Options
{
    devMode:      bool             // Whether 'dm' selected the DevMode compiler.
    command:      String           // The command, when the tool accepts more than one.
    module:       String           // The module, suite, or script that was named.
    buildCfg:     String           // The configuration to build and run in.
    allConfigs:   bool             // Whether to repeat an aggregate tool in both configurations.
    wantHelp:     bool             // Whether the tool was asked to print its usage.
    targetArch:   String           // The architecture every output path is keyed on.
    runAsync:     bool             // Whether an application run returns after starting the process.
    workspace:    Arguments        // Flags only a run or a smoke understands.
    test:         Arguments        // Flags only a test command understands.
    extra:        Arguments        // Everything else, forwarded to the compiler.
    runArguments: Array'String     // The '--run-arg' values, without the flag.
}

public impl Options
{
    // Returns whether a run argument named `name` was already asked for.
    //
    // A tool that adds one of its own asks this first, so an explicit request always wins over
    // the default it would otherwise install.
    mtd const hasRunArgument(name: string)->bool
    {
        for value in .runArguments
        {
            let text = value.toString()
            if text == name do
                return true
            if @countof(text) > @countof(name) and text[0 until @countof(name)] == name and text[@countof(name)] == '=' do
                return true
        }

        return false
    }

    // Appends the run arguments as the compiler spells them, one '--run-arg' per value.
    mtd const appendRunArguments(arguments: *Arguments)
    {
        for value in .runArguments do
            arguments.add(["--run-arg", value.toString()])
    }

    // Appends everything the grammar did not recognize, in the order it was given.
    mtd const appendExtra(arguments: *Arguments)
    {
        arguments.addAll(.extra)
    }

    // Appends the flags that only mean something to a run or a smoke.
    //
    // They are kept apart from the forwarded ones because a tool that builds the standard
    // library first must not hand them to that build, which would refuse them.
    mtd const appendWorkspace(arguments: *Arguments)
    {
        arguments.addAll(.workspace)
    }

    // Appends flags that select which #test functions a test command executes.
    //
    // They are kept away from prerequisite build commands, which compile the same module but do
    // not accept test-only options.
    mtd const appendTest(arguments: *Arguments)
    {
        arguments.addAll(.test)
    }

    // Returns the configurations this invocation asks for.
    mtd const configurations()->Array'String
    {
        var result: retval
        if !.allConfigs
        {
            result.add(.buildCfg)
            return result
        }

        for value in allConfigurations() do
            result.add(String.from(value))
        return result
    }
}

// The named options of the shared grammar, one field per option a tool understands.
//
// Core's command-line system fills this by reflection: an option designates the field its name
// matches, ignoring case and dashes, or the alias 'ArgParams' names, so '--build-cfg' and
// '-bc' both land in 'buildCfg'. What designates no field is captured verbatim and forwarded.
private struct Grammar
{
    #[CommandLine.ArgParams("h")]
    help: bool     // Print the tool's usage instead of running it.

    #[CommandLine.ArgParams("bc")]
    buildCfg: String     // The configuration to build and run in.

    allCfg: bool     // Repeat an aggregate tool in both configurations.

    #[CommandLine.ArgParams("m")]
    workspaceModule: String     // The module, when named through an option rather than the positional.

    targetArch: String           // The architecture every output path is keyed on, forwarded too.
    frames:     String           // Bound a run or a smoke to that many frames.
    runTimeout: String           // Fail a run or a smoke that outlives that many seconds.
    runArg:     Array'String     // One argument for the launched program, repeatable.
    testFile:   Array'String     // Source-path substrings whose #test functions should run.

    #[CommandLine.ArgParams("async")]
    runAsync: bool     // Return after starting an application instead of waiting for it.
}

// Parses the shared grammar, given the commands this tool accepts.
public func parseOptions(acceptedCommands: const [..] string, tokens: const [..] string)->Options fail
{
    var result: retval
    result.buildCfg   = String.from("devmode")
    result.targetArch = String.from("x86_64")

    // `/?` asks for help in the one spelling Core's parser has no dash for.
    for token in tokens
    {
        if token == "/?"
        {
            result.wantHelp = true
            return result
        }
    }

    var grammar: Grammar
    let parsed = try CommandLine.parse(&grammar, tokens, CommandLine.ParseOptions{capturePositionals: true, captureUnknown: true})
    if grammar.help
    {
        result.wantHelp = true
        return result
    }

    // The positional part: [dm] [<command>] [<name>], anything further forwarded untouched.
    var index = 0'u64
    if index < parsed.positionals.count and parsed.positionals[index] == "dm"
    {
        result.devMode = true
        index          += 1
    }

    if index < parsed.positionals.count
    {
        for accepted in acceptedCommands
        {
            if isCommand(parsed.positionals[index].toString(), accepted)
            {
                result.command = parsed.positionals[index]
                index          += 1
                break
            }
        }
    }

    if index < parsed.positionals.count
    {
        result.module = parsed.positionals[index]
        index         += 1
    }

    while index < parsed.positionals.count
    {
        result.extra.add([parsed.positionals[index].toString()])
        index += 1
    }

    // The named options, mapped onto what the tools act on.
    if parsed.isSet.buildCfg do
        result.buildCfg = grammar.buildCfg
    if parsed.isSet.workspaceModule do
        result.module = grammar.workspaceModule
    result.allConfigs   = grammar.allCfg
    result.runAsync     = grammar.runAsync
    result.runArguments = grammar.runArg

    if parsed.isSet.targetArch
    {
        result.targetArch = grammar.targetArch
        result.extra.add(["--target-arch", result.targetArch.toString()])
    }

    if parsed.isSet.frames do
        result.workspace.add(["--frames", grammar.frames.toString()])
    if parsed.isSet.runTimeout do
        result.workspace.add(["--run-timeout", grammar.runTimeout.toString()])
    for value in grammar.testFile do
        result.test.add(["--test-file", value.toString()])

    for token in parsed.unknown do
        result.extra.add([token.toString()])

    return result
}

// Reports whether a positional spells the command `accepted`, whatever its case.
private func isCommand(token: string, accepted: string)->bool
{
    return Utf8.compare(cast(const [..] u8) token, cast(const [..] u8) accepted, .Latin1NoCase) == 0
}
