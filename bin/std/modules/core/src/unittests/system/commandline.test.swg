#global #if #command == Swag.CompilerCommand.Test
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
    discard catch CommandLine.parse(&options, args)
    return @err != null
}

func parseAdvancedFailed(args: const [..] string)->bool
{
    var options: AdvancedOptions
    discard catch CommandLine.parse(&options, args)
    return @err != null
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
    let args: [4] string = [" -threshold = -.5 ", "-values:-1", " 2 ", " 3 "]
    let split = CommandLine.splitArguments(args, CommandLine.ParseOptions{})

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
    let fieldByName = CommandLine.getField(#typeof(NameOptions), "name")
    let fieldByAlias = CommandLine.getField(#typeof(NameOptions), "n")

    @assert(fieldByName.field != null)
    @assert(fieldByAlias.field != null)
    @assert(fieldByName.index == 0)
    @assert(fieldByAlias.index == 0)
}

#test
{
    var options: NameOptions
    let result = catch CommandLine.parse(&options, ["-n:Alice"])
    @assert(@err == null)

    @assert(options.name == "Alice")
    @assert(result.isSet.name)
}

#test
{
    var options: NameOptions
    let result = catch CommandLine.parse(&options, ["-n:-Alice"])
    @assert(@err == null)

    @assert(options.name == "-Alice")
    @assert(result.isSet.name)
}

#test
{
    var options: NumericOptions
    let result = catch CommandLine.parse(&options, ["-enabled", "false"])
    @assert(@err == null)

    @assert(options.enabled == false)
    @assert(result.isSet.enabled)
    @assert(!result.isSet.threshold)
}

#test
{
    var value = 0'f32
    let rest = catch StrConv.parseValue(&value, f32, "-0.5")
    @assert(@err == null)
    @assert(@countof(rest) == 0)
    @assert(value == -0.5)
}

#test
{
    var options: NumericOptions
    let result = catch CommandLine.parse(&options, ["-threshold", "-0.5"])
    @assert(@err == null)

    @assert(options.threshold == -0.5)
    @assert(result.isSet.threshold)
    @assert(!result.isSet.enabled)
}

#test
{
    var options: ArrayOptions
    let result = catch CommandLine.parse(&options, ["-values:-1", "2", "3"])
    @assert(@err == null)

    @assert(assertIntValues(options.values, [-1, 2, 3]))
    @assert(!result.isSet.labels)
    @assert(result.isSet.values)
}

#test
{
    var options: ArrayOptions
    let result = catch CommandLine.parse(&options, ["-labels", "Bob Smith", "Alice"])
    @assert(@err == null)

    @assert(assertStringValues(options.labels, ["Bob Smith", "Alice"]))
    @assert(!result.isSet.values)
    @assert(result.isSet.labels)
}

#test
{
    var options: ArrayOptions
    let result = catch CommandLine.parse(&options, ["-labels:-Bob", "Alice"])
    @assert(@err == null)

    @assert(assertStringValues(options.labels, ["-Bob", "Alice"]))
    @assert(!result.isSet.values)
    @assert(result.isSet.labels)
}

#test
{
    @assert(parseFailed(["-missing", "42"]))
    @assert(parseFailed(["-count"]))
    @assert(parseFailed(["-count", "nope"]))
    @assert(parseAdvancedFailed(["-labels"]))
    @assert(parseAdvancedFailed(["-values"]))
    @assert(parseAdvancedFailed(["-threshold", "-"]))
}
