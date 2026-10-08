#global export
#global namespace CommandLine

using Core.Errors

// Overrides the command-line name associated with a reflected field.
attr ArgParams(nameAlias: string? = null)

// Selects how [[Core.CommandLine.parse]] treats the tokens that designate no field.
struct ParseOptions
{
    public
    {
        capturePositionals: bool     // Collect the leading non-option tokens instead of failing on them.
        captureUnknown:     bool     // Collect the tokens that name no field, verbatim, instead of failing on them.
    }
}

// Mirrors the fields of `T` as `bool` values that record which options a parse set.
//
// Each field has the name of the corresponding field of `T`. After
// [[Core.CommandLine.parse]], a field is true when the command line assigned the matching
// option.
struct(T) IsSet
{
    public
    {
        #ast
        {
            var builder: StrConv.StringBuilder
            let typeInfo = #typeof(T)
            for field in typeInfo.fields do
                builder.appendFormat("%: bool\n", field.name)
            let generated = builder.moveToString()
            return generated.toString()
        }
    }
}

// Describes what [[Core.CommandLine.parse]] found besides the values it stored.
struct(T) Result
{
    public
    {
        isSet:       IsSet'T          // Which fields of `T` the command line assigned.
        positionals: Array'String     // The leading non-option tokens, in order, when 'capturePositionals' is set.
        unknown:     Array'String     // The tokens that named no field, verbatim and in order, when 'captureUnknown' is set.
    }
}

// Returns whether `oneArg` is an option, that is, whether it starts with '-'.
func isOption(oneArg: string, _: ParseOptions)->bool => oneArg.count != 0 and oneArg[0] == '-'

// Returns whether `oneArg` can be the value of a field of type `typeField` rather than an option.
//
// A token that is not an option is always a value. A token starting with '-' is a value only
// for a numeric field, when it spells a negative number.
func isValue(oneArg: string, typeField: typeinfo, options: ParseOptions)->bool
{
    if not isOption(oneArg, options) do
        return true

    let concreteType = Reflection.resolveAliases(typeField)

    if not Reflection.isInteger(concreteType) and not Reflection.isFloat(concreteType) do
        return false

    if oneArg.count < 2 do
        return false
    if not Latin1.isDigit(oneArg[1])
    {
        if not Reflection.isFloat(concreteType) do
            return false
        if oneArg[1] != '.'u8 or oneArg.count < 3 or not Latin1.isDigit(oneArg[2]) do
            return false
    }

    return true
}

private struct SplitArgument
{
    value:         string
    raw:           string     // The token as given, before name/value splitting, so it can be reported or forwarded verbatim.
    attachedValue: bool
}

private func splitArgumentsEx(args: const [..] string, options: ParseOptions)->Array'SplitArgument
{
    var result: retval

    for rawArgument in args
    {
        let argument = Latin1.trim(rawArgument)
        if not argument.count do
            continue

        if not isOption(argument, options)
        {
            result.add(SplitArgument{value: argument, raw: argument})
            continue
        }

        let split = Tokenize.splitAny(argument, [':'rune, '='rune], 1)
        if split.count == 2
        {
            let name = Latin1.trim(split[0])
            result.add(SplitArgument{value: name, raw: argument})
            let value = Latin1.trim(split[1])
            if value.count do
                result.add(SplitArgument{value: value, raw: "", attachedValue: true})
        }
        else
        {
            result.add(SplitArgument{value: argument, raw: argument})
        }
    }

    return result
}

// Returns `args` trimmed, without empty tokens, and with every `-option:value` or `-option=value` token split in two.
//
// The returned strings borrow from `args`.
func splitArguments(args: const [..] string, options: ParseOptions)->Array'(string)
{
    var result: retval
    for it in splitArgumentsEx(args, options) do
        result.add(it.value)
    return result
}

// Locates the field of a struct that an option designates.
struct FieldResult
{
    public
    {
        field: const *Swag.TypeValue?     // Designated field, or null when the option designates none.
        index: u64 = Swag.U64.Max         // Index of the field in its struct, or [[Swag.U64.Max]] when there is none.
    }
}

// Returns whether the option name `name` designates the declared name `candidate`.
//
// The comparison ignores case and the '-' and '_' separators, so an option spelled
// 'build-cfg' designates a field declared 'buildCfg'.
func isSameName(candidate: string, name: string)->bool
{
    let countCandidate = candidate.count
    let countName      = name.count

    var atCandidate = 0'u64
    var atName      = 0'u64
    for
    {
        while atCandidate < countCandidate and (candidate[atCandidate] == '-'u8 or candidate[atCandidate] == '_'u8) do
            atCandidate += 1
        while atName < countName and (name[atName] == '-'u8 or name[atName] == '_'u8) do
            atName += 1
        if atCandidate == countCandidate or atName == countName do
            break
        if Latin1.toLower(candidate[atCandidate]) != Latin1.toLower(name[atName]) do
            return false
        atCandidate += 1
        atName      += 1
    }

    return atCandidate == countCandidate and atName == countName
}

// Returns the field of `typeStruct` whose name or [[Core.CommandLine.ArgParams]] alias designates the option `name`.
//
// Names are matched like [[Core.CommandLine.isSameName]] does. The result has a null `field`
// when no field matches.
func getField(typeStruct: const *Swag.TypeInfoStruct, name: string)->FieldResult
{
    var result: retval

    for &field, index in typeStruct.fields
    {
        if isSameName(field.name orelse "", name)
        {
            result.field = field
            result.index = index
            return result
        }

        let aliasName = Reflection.attributeValue(field, ArgParams, "nameAlias", cast(string?, null))
        if aliasName != null and isSameName(aliasName orelse "", name)
        {
            result.field = field
            result.index = index
            return result
        }
    }

    return result
}

// Parses `args` into the fields of `st` and returns which fields were set.
//
// An option is written `-name`, `--name`, `-name value`, or `-name:value` (`=` works like
// `:`), and designates the field of `T` whose name or 'ArgParams' alias it matches, ignoring
// case and the '-'/'_' separators. What matches nothing fails the parse, unless the options
// ask for it to be captured: 'capturePositionals' collects the leading non-option tokens, and
// 'captureUnknown' collects every unrecognized token verbatim, which is how a caller forwards
// what it does not understand to another program.
func(T) parse(st: *T, args: const [..] string, options = ParseOptions{})->Result fail
{
    #[Swag.Mixin]
    func requireNextValue(typeField: typeinfo) fail
    {
        if argumentIndex + 1 == argumentCount do
            fail SyntaxError{Errors.mkString(Format.toString("missing value for option [[%]]", argument))}

        let nextArg = tokens[argumentIndex + 1]
        if not nextArg.attachedValue and not isValue(nextArg.value, typeField, options) do
            fail SyntaxError{Errors.mkString(Format.toString("missing value for option [[%]]", argument))}
    }

    var result: retval

    let tokens = splitArgumentsEx(args, options)

    // Resolve each option before writing its value.
    let typeInfo      = #typeof(T)
    let argumentCount = tokens.count
    var seenOption    = false
    for var argumentIndex = 0; argumentIndex < argumentCount; argumentIndex += 1
    {
        var argument = tokens[argumentIndex].value
        if not isOption(argument, options)
        {
            if options.capturePositionals and not seenOption
            {
                result.positionals.add(String.from(argument))
                continue
            }

            if options.captureUnknown
            {
                result.unknown.add(String.from(tokens[argumentIndex].raw))
                continue
            }

            fail SyntaxError{Errors.mkString(Format.toString("invalid option [[%]]", argument))}
        }

        seenOption = true

        // One leading dash or two spell the same option, so '--name' and '-name' both reach 'name'.
        argument = Tokenize.eatCount(argument, 1)
        if argument.count and argument[0] == '-' do
            argument = Tokenize.eatCount(argument, 1)

        let fieldResult = getField(typeInfo, argument)
        let field       = fieldResult.field
        if not field
        {
            if options.captureUnknown
            {
                // The raw spelling already carries an attached value, so its split half is dropped.
                result.unknown.add(String.from(tokens[argumentIndex].raw))
                if argumentIndex + 1 < argumentCount and tokens[argumentIndex + 1].attachedValue do
                    argumentIndex += 1
                continue
            }

            fail SyntaxError{Errors.mkString(Format.toString("unknown option [[%]]", argument))}
        }

        let typeField   = field.pointedType orelse #typeof(u8)
        let destination = cast([*] u8, st) + field.offset

        // Bool: Result is true if the option does not have an associated value
        if Reflection.isBool(typeField) and
           (argumentIndex + 1 == argumentCount or isOption(tokens[argumentIndex + 1].value, options))
        {
            cast(*bool, destination)[] = true
        }
        // Parse scalar values through the same reflected storage contract.
        elif typeField == #typeof(Core.String) or
             Reflection.isInteger(typeField) or
             Reflection.isFloat(typeField) or
             Reflection.isBool(typeField) or
             Reflection.isRune(typeField) or
             Reflection.isEnum(typeField)
        {
            try requireNextValue(typeField)
            var remaining = ""
            catch
            {
                remaining = try StrConv.parseValue(destination, typeField, tokens[argumentIndex + 1].value)
            } as err
            argumentIndex += 1

            if err != null or remaining.count do
                fail SyntaxError{Errors.mkString(Format.toString("invalid value for option [[%]]", argument))}
        }
        // Dynamic array of values
        elif Reflection.isDynamicArray(typeField)
        {
            let elementType = Reflection.dynamicArrayElementType(typeField) orelse #typeof(u8)
            try requireNextValue(elementType)

            let isStringElement = elementType == Core.String

            // Quote string elements so spaces remain inside their values.
            var collectedValues: String
            while argumentIndex + 1 != argumentCount
            {
                let nextArg = tokens[argumentIndex + 1]
                if not nextArg.attachedValue and not isValue(nextArg.value, elementType, options) do
                    break

                var value = nextArg.value
                if isStringElement
                {
                    value = Tokenize.eatQuotes(value)
                    collectedValues.append("\"")
                }

                collectedValues.append(value)

                if isStringElement do
                    collectedValues.append("\"")

                collectedValues.append(" ")
                argumentIndex += 1
            }

            if not collectedValues.isEmpty()
            {
                catch { discard try StrConv.parseValue(destination, typeField, collectedValues.toString()) } as err
                if err != null do
                    fail SyntaxError{Errors.mkString(Format.toString("invalid value for option [[%]]", argument))}
            }
        }
        else
        {
            let message = Format.toString("unsupported type [[%]] for option [[%]]", typeField.name, argument)
            fail UnsupportedFormatError{Errors.mkString(message)}
        }

        // 'IsSet' holds one 'bool' per field of 'T', in field order.
        cast([*] bool, &result.isSet)[fieldResult.index] = true
    }

    return result
}
