#global if #command == Swag.CompilerCommand.Test
#global private

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
    delta:   s32
    count:   s32
    enabled: bool
    mode:    ParseMode
}

struct AdvancedOptions
{
    #[CommandLine.ArgParams(nameAlias: "n")]
    name:      String
    enabled:   bool
    threshold: f32
    values:    Array's32
    labels:    Array'String
}

struct NameOptions
{
    #[CommandLine.ArgParams(nameAlias: "n")]
    name: String
}

struct NumericOptions
{
    enabled:   bool
    threshold: f32
}

struct ArrayOptions
{
    values: Array's32
    labels: Array'String
}

func parseFailed(args: const [..] string)->bool
{
    var options: BasicOptions
    discard catch CommandLine.parse(&options, args) as err
    return err != null
}

func parseAdvancedFailed(args: const [..] string)->bool
{
    var options: AdvancedOptions
    discard catch CommandLine.parse(&options, args) as err2
    return err2 != null
}

func assertIntValues(values: const &Array's32, expected: const [..] s32)->bool
{
    if values.count != @countof(expected) do
        return false

    for i in values.count
    {
        if values[i] != expected[i] do
            return false
    }

    return true
}

func assertStringValues(values: const &Array'String, expected: const [..] string)->bool
{
    if values.count != @countof(expected) do
        return false

    for i in values.count
    {
        if values[i] != expected[i] do
            return false
    }

    return true
}

#test
{
    let args: [4] string = ["  -name:Bob  ", " -count = 42 ", "", "payload"]
    let split            = CommandLine.splitArguments(args, CommandLine.ParseOptions{})

    @assert(split.count == 5)
    @assert(split[0] == "-name")
    @assert(split[1] == "Bob")
    @assert(split[2] == "-count")
    @assert(split[3] == "42")
    @assert(split[4] == "payload")
}

#test
{
    let args: [4] string = [" -threshold = -.5 ", "-values:-1", " 2 ", " 3 "]
    let split            = CommandLine.splitArguments(args, CommandLine.ParseOptions{})

    @assert(split.count == 6)
    @assert(split[0] == "-threshold")
    @assert(split[1] == "-.5")
    @assert(split[2] == "-values")
    @assert(split[3] == "-1")
    @assert(split[4] == "2")
    @assert(split[5] == "3")
}

#test
{
    var options          = BasicOptions{}
    let args: [7] string = ["-delta", "-7", "-count", "-12", "-enabled", "-mode", "Gamma"]

    let result = expect CommandLine.parse(&options, args)

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
    let fieldByName  = CommandLine.getField(#typeof(NameOptions), "name")
    let fieldByAlias = CommandLine.getField(#typeof(NameOptions), "n")

    @assert(fieldByName.field != null)
    @assert(fieldByAlias.field != null)
    @assert(fieldByName.index == 0)
    @assert(fieldByAlias.index == 0)
}

#test
{
    var options: NameOptions
    let result = expect CommandLine.parse(&options, ["-n:Alice"])
    @assert(options.name == "Alice")
    @assert(result.isSet.name)
}

#test
{
    var options: NameOptions
    let result = expect CommandLine.parse(&options, ["-n:-Alice"])
    @assert(options.name == "-Alice")
    @assert(result.isSet.name)
}

#test
{
    var options: NumericOptions
    let result = expect CommandLine.parse(&options, ["-enabled", "false"])
    @assert(options.enabled == false)
    @assert(result.isSet.enabled)
    @assert(!result.isSet.threshold)
}

#test
{
    var value = 0'f32
    let rest  = expect StrConv.parseValue(&value, f32, "-0.5")
    @assert(@countof(rest) == 0)
    @assert(value == -0.5)
}

#test
{
    var options: NumericOptions
    let result = expect CommandLine.parse(&options, ["-threshold", "-0.5"])
    @assert(options.threshold == -0.5)
    @assert(result.isSet.threshold)
    @assert(!result.isSet.enabled)
}

#test
{
    var options: ArrayOptions
    let result = expect CommandLine.parse(&options, ["-values:-1", "2", "3"])
    @assert(assertIntValues(options.values, [-1, 2, 3]))
    @assert(!result.isSet.labels)
    @assert(result.isSet.values)
}

#test
{
    var options: ArrayOptions
    let result = expect CommandLine.parse(&options, ["-labels", "Bob Smith", "Alice"])
    @assert(assertStringValues(options.labels, ["Bob Smith", "Alice"]))
    @assert(!result.isSet.values)
    @assert(result.isSet.labels)
}

#test
{
    var options: ArrayOptions
    let result = expect CommandLine.parse(&options, ["-labels:-Bob", "Alice"])
    @assert(assertStringValues(options.labels, ["-Bob", "Alice"]))
    @assert(!result.isSet.values)
    @assert(result.isSet.labels)
}

#test
{
    @assert(parseFailed(["-missing", "42"]))
    @assert(parseFailed(["-count"]))
    @assert(parseFailed(["-count", "nope"]))
    @assert(parseFailed(["stray-positional"]))
    @assert(parseAdvancedFailed(["-labels"]))
    @assert(parseAdvancedFailed(["-values"]))
    @assert(parseAdvancedFailed(["-threshold", "-"]))
}

// A double dash, a different case, and the '-'/'_' separators all reach the same field.
#test
{
    var options: BasicOptions
    let result = expect CommandLine.parse(&options, ["--delta", "-7", "-Count", "-12", "--e-na_bled"])

    @assert(options.delta == -7)
    @assert(options.count == -12)
    @assert(options.enabled)
    @assert(result.isSet.delta and result.isSet.count and result.isSet.enabled)
}

// The leading non-option tokens become positionals when asked for, and parsing goes on.
#test
{
    var options: BasicOptions
    let result = expect CommandLine.parse(&options, ["run", "snake", "-count", "3"], CommandLine.ParseOptions{capturePositionals: true})

    @assert(result.positionals.count == 2)
    @assert(result.positionals[0] == "run")
    @assert(result.positionals[1] == "snake")
    @assert(options.count == 3)
    @assert(result.unknown.isEmpty())
}

// What names no field is captured verbatim and in order, values included, so a caller can
// forward it to another program.
#test
{
    var options: BasicOptions
    let result = expect CommandLine.parse(&options, ["--seed", "123", "-count", "3", "--rebuild", "--out:dir with space"], CommandLine.ParseOptions{captureUnknown: true})

    @assert(options.count == 3)
    @assert(result.unknown.count == 4)
    @assert(result.unknown[0] == "--seed")
    @assert(result.unknown[1] == "123")
    @assert(result.unknown[2] == "--rebuild")
    @assert(result.unknown[3] == "--out:dir with space")
}

// An array option appends at each occurrence instead of restarting.
#test
{
    var options: ArrayOptions
    let result = expect CommandLine.parse(&options, ["-labels", "Bob", "-labels", "Alice"])
    @assert(assertStringValues(options.labels, ["Bob", "Alice"]))
    @assert(result.isSet.labels)
}
