#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag

enum ParseMode
{
    Alpha
    Beta
    Gamma
}

struct BasicOptions
{
    #[CommandLine.ArgParams(nameAlias: "n")]
    delta: s32
    count: s32
    enabled: bool
    mode: ParseMode
}

func parseFailed(args: const [..] string)->bool
{
    var options: BasicOptions
    discard catch CommandLine.parse(&options, args)
    return @err != null
}

#test
{
    let args: [4] string = ["  -name:Bob  ", " -count = 42 ", "", "payload"]
    let split = CommandLine.splitArguments(args, CommandLine.ParseOptions{})

    @assert(split.count == 5)
    @assert(split[0] == "-name")
    @assert(split[1] == "Bob")
    @assert(split[2] == "-count")
    @assert(split[3] == "42")
    @assert(split[4] == "payload")
}

#test
{
    var options = BasicOptions{}
    let args: [7] string = ["-delta", "-7", "-count", "-12", "-enabled", "-mode", "Gamma"]

    let result = catch CommandLine.parse(&options, args)

    @assert(options.delta == -7)
    @assert(options.count == -12)
    @assert(options.enabled)
    @assert(options.mode == .Gamma)

    @assert(result.isSet.delta)
    @assert(result.isSet.count)
    @assert(result.isSet.enabled)
    @assert(result.isSet.mode)
}

#test
{
    @assert(parseFailed(["-missing", "42"]))
    @assert(parseFailed(["-count"]))
    @assert(parseFailed(["-count", "nope"]))
}
