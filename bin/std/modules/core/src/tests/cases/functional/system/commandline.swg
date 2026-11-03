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
    var options:    BasicOptions
    var errOutcome: Swag.Error
    discard catch CommandLine.parse(&options, args) as errOutcome
    let err = errOutcome.value()
    return err != null
}

func parseAdvancedFailed(args: const [..] string)->bool
{
    var options:     AdvancedOptions
    var err2Outcome: Swag.Error
    discard catch CommandLine.parse(&options, args) as err2Outcome
    let err2 = err2Outcome.value()
    return err2 != null
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
    let split = CommandLine.splitArguments(args, {})

    Swag.require(split.count == 5)
    Swag.require(split[0] == "-name")
    Swag.require(split[1] == "Bob")
    Swag.require(split[2] == "-count")
    Swag.require(split[3] == "42")
    Swag.require(split[4] == "payload")
}

#test
{
    let args: [4] string = [" -threshold = -.5 ", "-values:-1", " 2 ", " 3 "]
    let split = CommandLine.splitArguments(args, {})

    Swag.require(split.count == 6)
    Swag.require(split[0] == "-threshold")
    Swag.require(split[1] == "-.5")
    Swag.require(split[2] == "-values")
    Swag.require(split[3] == "-1")
    Swag.require(split[4] == "2")
    Swag.require(split[5] == "3")
}

#test
{
    var options = BasicOptions{}
    let args: [7] string = ["-delta", "-7", "-count", "-12", "-enabled", "-mode", "Gamma"]

    let result = expect CommandLine.parse(&options, args)

    Swag.require(options.delta == -7)
    Swag.require(options.count == -12)
    Swag.require(options.enabled)
    Swag.require(options.mode == .Gamma)

    Swag.require(result.isSet.delta)
    Swag.require(result.isSet.count)
    Swag.require(result.isSet.enabled)
    Swag.require(result.isSet.mode)
}

#test
{
    let fieldByName  = CommandLine.getField(#typeof(NameOptions), "name")
    let fieldByAlias = CommandLine.getField(#typeof(NameOptions), "n")

    Swag.require(fieldByName.field != null)
    Swag.require(fieldByAlias.field != null)
    Swag.require(fieldByName.index == 0)
    Swag.require(fieldByAlias.index == 0)
}

#test
{
    var options: NameOptions
    let result = expect CommandLine.parse(&options, ["-n:Alice"])
    Swag.require(options.name == "Alice")
    Swag.require(result.isSet.name)
}

#test
{
    var options: NameOptions
    let result = expect CommandLine.parse(&options, ["-n:-Alice"])
    Swag.require(options.name == "-Alice")
    Swag.require(result.isSet.name)
}

#test
{
    var options: NameOptions
    let result = expect CommandLine.parse(&options, ["-n=", "Alice"], {captureUnknown: true})
    let split  = CommandLine.splitArguments(["-n="], {})

    Swag.require(options.name.isEmpty())
    Swag.require(result.isSet.name)
    Swag.require(result.unknown.count == 1 and result.unknown[0] == "Alice")
    Swag.require(split.count == 1 and split[0] == "-n")
    Swag.require(parseFailed(["-count=", "42"]))
}

#test
{
    var options: NumericOptions
    let result = expect CommandLine.parse(&options, ["-enabled", "false"])
    Swag.require(not options.enabled)
    Swag.require(result.isSet.enabled)
    Swag.require(not result.isSet.threshold)
}

#test
{
    var value = 0'f32
    let rest  = expect StrConv.parseValue(&value, f32, "-0.5")
    Swag.require(rest.count == 0)
    Swag.require(value == -0.5)
}

#test
{
    var options: NumericOptions
    let result = expect CommandLine.parse(&options, ["-threshold", "-0.5"])
    Swag.require(options.threshold == -0.5)
    Swag.require(result.isSet.threshold)
    Swag.require(not result.isSet.enabled)
}

#test
{
    var options: ArrayOptions
    let result = expect CommandLine.parse(&options, ["-values:-1", "2", "3"])
    Swag.require(Slice.equals(options.values.toSlice(), [-1, 2, 3]))
    Swag.require(not result.isSet.labels)
    Swag.require(result.isSet.values)
}

#test
{
    var options: ArrayOptions
    let result = expect CommandLine.parse(&options, ["-labels", "Bob Smith", "Alice"])
    Swag.require(assertStringValues(options.labels, ["Bob Smith", "Alice"]))
    Swag.require(not result.isSet.values)
    Swag.require(result.isSet.labels)
}

#test
{
    var options: ArrayOptions
    let result = expect CommandLine.parse(&options, ["-labels:-Bob", "Alice"])
    Swag.require(assertStringValues(options.labels, ["-Bob", "Alice"]))
    Swag.require(not result.isSet.values)
    Swag.require(result.isSet.labels)
}

#test
{
    Swag.require(parseFailed(["-missing", "42"]))
    Swag.require(parseFailed(["-count"]))
    Swag.require(parseFailed(["-count", "nope"]))
    Swag.require(parseFailed(["stray-positional"]))
    Swag.require(parseAdvancedFailed(["-labels"]))
    Swag.require(parseAdvancedFailed(["-values"]))
    Swag.require(parseAdvancedFailed(["-threshold", "-"]))
}

// A double dash, a different case, and the '-'/'_' separators all reach the same field.
#test
{
    var options: BasicOptions
    let result = expect CommandLine.parse(&options, ["--delta", "-7", "-Count", "-12", "--e-na_bled"])

    Swag.require(options.delta == -7)
    Swag.require(options.count == -12)
    Swag.require(options.enabled)
    Swag.require(result.isSet.delta and result.isSet.count and result.isSet.enabled)
}

// The leading non-option tokens become positionals when asked for, and parsing goes on.
#test
{
    var options: BasicOptions
    let result = expect CommandLine.parse(&options, ["run", "snake", "-count", "3"], {capturePositionals: true})

    Swag.require(result.positionals.count == 2)
    Swag.require(result.positionals[0] == "run")
    Swag.require(result.positionals[1] == "snake")
    Swag.require(options.count == 3)
    Swag.require(result.unknown.isEmpty())
}

// What names no field is captured verbatim and in order, values included, so a caller can
// forward it to another program.
#test
{
    var options: BasicOptions
    let result = expect CommandLine.parse(&options, ["--seed", "123", "-count", "3", "--rebuild", "--out:dir with space"], {captureUnknown: true})

    Swag.require(options.count == 3)
    Swag.require(result.unknown.count == 4)
    Swag.require(result.unknown[0] == "--seed")
    Swag.require(result.unknown[1] == "123")
    Swag.require(result.unknown[2] == "--rebuild")
    Swag.require(result.unknown[3] == "--out:dir with space")
}

// An array option appends at each occurrence instead of restarting.
#test
{
    var options: ArrayOptions
    let result = expect CommandLine.parse(&options, ["-labels", "Bob", "-labels", "Alice"])
    Swag.require(assertStringValues(options.labels, ["Bob", "Alice"]))
    Swag.require(result.isSet.labels)
}
