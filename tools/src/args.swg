#global namespace Tool

using Core

/*
The argument grammar every repository tool shares.

    tool [dm] [<command>] [<name>] [options...]

Positionals come first and options after, so an option value can never be mistaken for a name:
the first token starting with `-` or `/` closes the positional part. Anything the grammar does
not know is forwarded to the compiler untouched, which is what lets a caller pass `--seed` or
`--num-cores` through any tool.
*/
public struct Options
{
    devMode:      bool                    // Whether 'dm' selected the DevMode compiler.
    command:      String                  // The command, when the tool accepts more than one.
    module:       String                  // The module, suite, or script that was named.
    buildCfg:     String                  // The configuration to build and run in.
    allConfigs:   bool                    // Whether to repeat an aggregate tool in all three.
    wantHelp:     bool                    // Whether the tool was asked to print its usage.
    targetArch:   String                  // The architecture every output path is keyed on.
    workspace:    Arguments             // Flags only a run or a smoke understands.
    extra:        Arguments             // Everything else, forwarded to the compiler.
    runArguments: Array'String            // The '--run-arg' values, without the flag.
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

// Parses the shared grammar, given the commands this tool accepts.
public func parseOptions(acceptedCommands: const [..] string, tokens: const [..] String)->Options fail
{
    var result: retval
    result.buildCfg   = String.from("fast-debug")
    result.targetArch = String.from("x86_64")

    var index = 0'u64
    let count = @countof(tokens)

    if index < count and tokens[index].toString() == "dm"
    {
        result.devMode = true
        index += 1
    }

    if index < count and !isOption(tokens[index].toString())
    {
        let token = tokens[index].toString()
        for accepted in acceptedCommands
        {
            if Utf8.compare(cast(const [..] u8) token, cast(const [..] u8) accepted, .Latin1NoCase) == 0
            {
                result.command = token
                index += 1
                break
            }
        }
    }

    if index < count and !isOption(tokens[index].toString())
    {
        result.module = tokens[index]
        index += 1
    }

    while index < count
    {
        let token = tokens[index].toString()
        index += 1

        if matches(token, "-h") or matches(token, "--help") or token == "/?"
        {
            result.wantHelp = true
            return result
        }

        if matches(token, "--all-cfg")
        {
            result.allConfigs = true
            continue
        }

        if matches(token, "-bc") or matches(token, "--build-cfg")
        {
            result.buildCfg = try takeValue(tokens, &index, token)
            continue
        }

        if matches(token, "-m") or matches(token, "--workspace-module")
        {
            result.module = try takeValue(tokens, &index, token)
            continue
        }

        if matches(token, "--target-arch")
        {
            result.targetArch = try takeValue(tokens, &index, token)
            result.extra.add(["--target-arch", result.targetArch.toString()])
            continue
        }

        if matches(token, "--frames") or matches(token, "--run-timeout")
        {
            let value = try takeValue(tokens, &index, token)
            result.workspace.add([token, value.toString()])
            continue
        }

        if matches(token, "--run-arg")
        {
            result.runArguments.add(try takeValue(tokens, &index, token))
            continue
        }

        result.extra.add([token])
    }

    return result
}

// Reports whether `token` closes the positional part of the command line.
private func isOption(token: string)->bool
{
    if @countof(token) == 0 do
        return false
    return token[0] == '-' or token[0] == '/'
}

private func matches(token: string, name: string)->bool
{
    return Utf8.compare(cast(const [..] u8) token, cast(const [..] u8) name, .Latin1NoCase) == 0
}

// Consumes the value that follows an option, failing when it is missing.
private func takeValue(tokens: const [..] String, index: *u64, option: string)->String fail
{
    if dref index >= @countof(tokens) do
        fail Errors.BadParameterError{Errors.mkString(Format.toString("option '%' is missing its value", option))}

    let value = tokens[dref index]
    dref index += 1
    return value
}
