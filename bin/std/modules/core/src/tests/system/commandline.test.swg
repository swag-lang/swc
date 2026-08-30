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

func assertIntValues(values: Array's32, expected: const [..] s32)->bool
{
    if values.count != expected.count do
        return false

    for i in values.count
    {
        if values[i] != expected[i] do
            return false
    }

    return true
}

func assertStringValues(values: Array'String, expected: const [..] string)->bool
{
    if values.count != expected.count do
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

    Swag.assert(split.count == 5)
    Swag.assert(split[0] == "-name")
    Swag.assert(split[1] == "Bob")
    Swag.assert(split[2] == "-count")
    Swag.assert(split[3] == "42")
    Swag.assert(split[4] == "payload")
}

#test
{
    let args: [4] string = [" -threshold = -.5 ", "-values:-1", " 2 ", " 3 "]
    let split            = CommandLine.splitArguments(args, CommandLine.ParseOptions{})

    Swag.assert(split.count == 6)
    Swag.assert(split[0] == "-threshold")
    Swag.assert(split[1] == "-.5")
    Swag.assert(split[2] == "-values")
    Swag.assert(split[3] == "-1")
    Swag.assert(split[4] == "2")
    Swag.assert(split[5] == "3")
}

#test
{
    var options          = BasicOptions{}
    let args: [7] string = ["-delta", "-7", "-count", "-12", "-enabled", "-mode", "Gamma"]

    let result = expect CommandLine.parse(&options, args)

    Swag.assert(options.delta == -7)
    Swag.assert(options.count == -12)
    Swag.assert(options.enabled)
    Swag.assert(options.mode == .Gamma)

    Swag.assert(result.isSet.delta)
    Swag.assert(result.isSet.count)
    Swag.assert(result.isSet.enabled)
    Swag.assert(result.isSet.mode)
}

#test
{
    let fieldByName  = CommandLine.getField(#typeof(NameOptions), "name")
    let fieldByAlias = CommandLine.getField(#typeof(NameOptions), "n")

    Swag.assert(fieldByName.field != null)
    Swag.assert(fieldByAlias.field != null)
    Swag.assert(fieldByName.index == 0)
    Swag.assert(fieldByAlias.index == 0)
}

#test
{
    var options: NameOptions
    let result = expect CommandLine.parse(&options, ["-n:Alice"])
    Swag.assert(options.name == "Alice")
    Swag.assert(result.isSet.name)
}

#test
{
    var options: NameOptions
    let result = expect CommandLine.parse(&options, ["-n:-Alice"])
    Swag.assert(options.name == "-Alice")
    Swag.assert(result.isSet.name)
}

#test
{
    var options: NumericOptions
    let result = expect CommandLine.parse(&options, ["-enabled", "false"])
    Swag.assert(options.enabled == false)
    Swag.assert(result.isSet.enabled)
    Swag.assert(!result.isSet.threshold)
}

#test
{
    var value = 0'f32
    let rest  = expect StrConv.parseValue(&value, f32, "-0.5")
    Swag.assert(rest.count == 0)
    Swag.assert(value == -0.5)
}

#test
{
    var options: NumericOptions
    let result = expect CommandLine.parse(&options, ["-threshold", "-0.5"])
    Swag.assert(options.threshold == -0.5)
    Swag.assert(result.isSet.threshold)
    Swag.assert(!result.isSet.enabled)
}

#test
{
    var options: ArrayOptions
    let result = expect CommandLine.parse(&options, ["-values:-1", "2", "3"])
    Swag.assert(assertIntValues(options.values, [-1, 2, 3]))
    Swag.assert(!result.isSet.labels)
    Swag.assert(result.isSet.values)
}

#test
{
    var options: ArrayOptions
    let result = expect CommandLine.parse(&options, ["-labels", "Bob Smith", "Alice"])
    Swag.assert(assertStringValues(options.labels, ["Bob Smith", "Alice"]))
    Swag.assert(!result.isSet.values)
    Swag.assert(result.isSet.labels)
}

#test
{
    var options: ArrayOptions
    let result = expect CommandLine.parse(&options, ["-labels:-Bob", "Alice"])
    Swag.assert(assertStringValues(options.labels, ["-Bob", "Alice"]))
    Swag.assert(!result.isSet.values)
    Swag.assert(result.isSet.labels)
}

#test
{
    Swag.assert(parseFailed(["-missing", "42"]))
    Swag.assert(parseFailed(["-count"]))
    Swag.assert(parseFailed(["-count", "nope"]))
    Swag.assert(parseFailed(["stray-positional"]))
    Swag.assert(parseAdvancedFailed(["-labels"]))
    Swag.assert(parseAdvancedFailed(["-values"]))
    Swag.assert(parseAdvancedFailed(["-threshold", "-"]))
}

// A double dash, a different case, and the '-'/'_' separators all reach the same field.
#test
{
    var options: BasicOptions
    let result = expect CommandLine.parse(&options, ["--delta", "-7", "-Count", "-12", "--e-na_bled"])

    Swag.assert(options.delta == -7)
    Swag.assert(options.count == -12)
    Swag.assert(options.enabled)
    Swag.assert(result.isSet.delta and result.isSet.count and result.isSet.enabled)
}

// The leading non-option tokens become positionals when asked for, and parsing goes on.
#test
{
    var options: BasicOptions
    let result = expect CommandLine.parse(&options, ["run", "snake", "-count", "3"], CommandLine.ParseOptions{capturePositionals: true})

    Swag.assert(result.positionals.count == 2)
    Swag.assert(result.positionals[0] == "run")
    Swag.assert(result.positionals[1] == "snake")
    Swag.assert(options.count == 3)
    Swag.assert(result.unknown.isEmpty())
}

// What names no field is captured verbatim and in order, values included, so a caller can
// forward it to another program.
#test
{
    var options: BasicOptions
    let result = expect CommandLine.parse(&options, ["--seed", "123", "-count", "3", "--rebuild", "--out:dir with space"], CommandLine.ParseOptions{captureUnknown: true})

    Swag.assert(options.count == 3)
    Swag.assert(result.unknown.count == 4)
    Swag.assert(result.unknown[0] == "--seed")
    Swag.assert(result.unknown[1] == "123")
    Swag.assert(result.unknown[2] == "--rebuild")
    Swag.assert(result.unknown[3] == "--out:dir with space")
}

// An array option appends at each occurrence instead of restarting.
#test
{
    var options: ArrayOptions
    let result = expect CommandLine.parse(&options, ["-labels", "Bob", "-labels", "Alice"])
    Swag.assert(assertStringValues(options.labels, ["Bob", "Alice"]))
    Swag.assert(result.isSet.labels)
}
