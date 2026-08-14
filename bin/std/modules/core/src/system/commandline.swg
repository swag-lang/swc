#global export
#global namespace CommandLine

using Core.Errors

// Overrides the command-line name associated with a reflected field.
attr ArgParams(nameAlias: #null string = null)

// Represents parse options.
struct ParseOptions
{
    public
    {
        capturePositionals: bool     // Collect the leading non-option tokens instead of failing on them.
        captureUnknown:     bool     // Collect the tokens that name no field, verbatim, instead of failing on them.
    }
}

// The 'IsSet' generic struct is a mirror of the user input struct.
//
// Each field has the same name as the original one, but with a 'bool' type.
//
// It will indicate, after the command line parsing, that the corresponding argument has been
// specified or not by the user.
struct(T) IsSet
{
    public
    {
        #ast
        {
            var str    = StrConv.StringBuilder{}
            let typeof = #typeof(T)
            for f in typeof.fields do
                str.appendFormat("%: bool\n", f.name)
            let generated = str.moveToString()
            return generated.toString()
        }
    }
}

// Result of the [parse] function
struct(T) Result
{
    public
    {
        isSet:       IsSet'T          // Whether this value is set.
        positionals: Array'String     // The leading non-option tokens, in order, when 'capturePositionals' is set.
        unknown:     Array'String     // The tokens that named no field, verbatim and in order, when 'captureUnknown' is set.
    }
}

// Returns true if 'oneArg' is a valid option (starting with a delimiter)
func isOption(oneArg: string, _options: ParseOptions)->bool
{
    if @countof(oneArg) == 0 do
        return false
    return oneArg[0] == '-'
}

// Returns whether value.
func isValue(oneArg: string, typeField: typeinfo, options: ParseOptions)->bool
{
    if !isOption(oneArg, options) do
        return true

    let concreteType = Reflection.resolveAliases(typeField)

    if !Reflection.isInteger(concreteType) and !Reflection.isFloat(concreteType) do
        return false

    if @countof(oneArg) < 2 do
        return false
    if !Latin1.isDigit(oneArg[1])
    {
        if !Reflection.isFloat(concreteType) do
            return false
        if oneArg[1] != '.'u8 or @countof(oneArg) < 3 or !Latin1.isDigit(oneArg[2]) do
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
    var allArgs: retval

    // Clean all arguments
    for it in args
    {
        var oneArg = it
        oneArg = Latin1.trim(oneArg)
        if !@countof(oneArg) do
            continue

        if !isOption(oneArg, options)
        {
            allArgs.add(SplitArgument{value: oneArg, raw: oneArg})
            continue
        }

        let split = Tokenize.splitAny(oneArg, [':'rune, '='rune], 1)
        if split.count == 2
        {
            let name = Latin1.trim(split[0])
            allArgs.add(SplitArgument{value: name, raw: oneArg})
            let other = Latin1.trim(split[1])
            if @countof(other) do
                allArgs.add(SplitArgument{value: other, raw: "", attachedValue: true})
        }
        else
        {
            allArgs.add(SplitArgument{value: oneArg, raw: oneArg})
        }
    }

    return allArgs
}

// Clean and split a list of arguments
// -option:value or -option=value => -option value
func splitArguments(args: const [..] string, options: ParseOptions)->Array'(string)
{
    var allArgs: retval

    for it in splitArgumentsEx(args, options)
    {
        allArgs.add(it.value)
    }

    return allArgs
}

// Represents field result.
struct FieldResult
{
    public
    {
        field: #null const *Swag.TypeValue     // Field associated with this value.
        index: u64 = Swag.U64.Max              // Index associated with this value.
    }
}

// Returns whether the option name `name` designates the declared name `candidate`.
//
// The comparison ignores case and the '-' and '_' separators, so an option spelled
// 'build-cfg' designates a field declared 'buildCfg'.
func isSameName(candidate: string, name: string)->bool
{
    let countCandidate = @countof(candidate)
    let countName      = @countof(name)

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

// Returns field.
func getField(typeStruct: const *Swag.TypeInfoStruct, name: string)->FieldResult
{
    var result: retval

    for &it in typeStruct.fields
    {
        // Test normal name (field)
        if isSameName(it.name orelse "", name)
        {
            result.field = it
            result.index = @index
            return result
        }

        // Test name alias
        let aliasName = Reflection.attributeValue(it, ArgParams, "nameAlias", cast(#null string) null)
        if aliasName != null and isSameName(aliasName orelse "", name)
        {
            result.field = it
            result.index = @index
            return result
        }
    }

    return result
}

// Parse all the arguments and fill the result
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
    func checkNext(typeField: typeinfo) fail
    {
        if itp + 1 == maxItp do
            fail SyntaxError{Errors.mkString(Format.toString("missing value for option [[%]]", oneArg))}

        let nextArg = allArgs[itp + 1]
        if !nextArg.attachedValue and !isValue(nextArg.value, typeField, options) do
            fail SyntaxError{Errors.mkString(Format.toString("missing value for option [[%]]", oneArg))}
    }

    var result: retval

    // First pass
    let allArgs = splitArgumentsEx(args, options)

    // Parse all
    let typeof     = #typeof(T)
    let maxItp     = @countof(allArgs)
    var seenOption = false
    for var itp = 0; itp < maxItp; itp += 1
    {
        var oneArg = allArgs[itp].value
        if !isOption(oneArg, options)
        {
            if options.capturePositionals and !seenOption
            {
                result.positionals.add(String.from(oneArg))
                continue
            }

            if options.captureUnknown
            {
                result.unknown.add(String.from(allArgs[itp].raw))
                continue
            }

            fail SyntaxError{Errors.mkString(Format.toString("invalid option [[%]]", oneArg))}
        }

        seenOption = true

        // One leading dash or two spell the same option, so '--name' and '-name' both reach 'name'.
        oneArg = Tokenize.eatCount(oneArg, 1)
        if @countof(oneArg) and oneArg[0] == '-' do
            oneArg = Tokenize.eatCount(oneArg, 1)

        let fieldResult = getField(typeof, oneArg)
        let typeParam   = fieldResult.field
        if !typeParam
        {
            if options.captureUnknown
            {
                // The raw spelling already carries an attached value, so its split half is dropped.
                result.unknown.add(String.from(allArgs[itp].raw))
                if itp + 1 < maxItp and allArgs[itp + 1].attachedValue do
                    itp += 1
                continue
            }

            fail SyntaxError{Errors.mkString(Format.toString("unknown option [[%]]", oneArg))}
        }

        let field     = typeParam
        let typeField = field.pointedType orelse #typeof(u8)

        var addr = cast([*] u8) st
        addr += field.offset

        // Bool: Result is true if the option does not have an associated value
        if Reflection.isBool(typeField) and
           (itp + 1 == maxItp or isOption(allArgs[itp + 1].value, options))
        {
            (cast(*bool) addr)[] = true
        }

        // All types supported by 'Parse.pokeValue'
        elif typeField == #typeof(Core.String) or
             Reflection.isInteger(typeField) or
             Reflection.isFloat(typeField) or
             Reflection.isBool(typeField) or
             Reflection.isRune(typeField) or
             Reflection.isEnum(typeField)
        {
            try checkNext(typeField)
            let rest = catch StrConv.parseValue(addr, typeField, allArgs[itp + 1].value) as err
            itp += 1

            if err != null do
                fail SyntaxError{Errors.mkString(Format.toString("invalid value for option [[%]]", oneArg))}
            if @countof(rest) do
                fail SyntaxError{Errors.mkString(Format.toString("invalid value for option [[%]]", oneArg))}
        }

        // Dynamic array of values
        elif Reflection.isDynamicArray(typeField)
        {
            let arrayType = Reflection.dynamicArrayElementType(typeField) orelse #typeof(u8)
            try checkNext(arrayType)

            // If it's an array of strings, we will need to add string delimiters
            // to each value
            let isString = arrayType == Core.String

            // Make one single string with all values, for pokeValue
            var collect: String
            while itp + 1 != maxItp
            {
                let nextArg = allArgs[itp + 1]
                if !nextArg.attachedValue and !isValue(nextArg.value, arrayType, options) do
                    break

                var other = nextArg.value
                if isString
                {
                    other = Tokenize.eatQuotes(other)
                    collect.append("\"")
                }

                collect.append(other)

                if isString do
                    collect.append("\"")

                collect.append(" ")
                itp += 1
            }

            if collect != null
            {
                discard catch StrConv.parseValue(addr, typeField, collect.toString()) as err
                if err != null do
                    fail SyntaxError{Errors.mkString(Format.toString("invalid value for option [[%]]", oneArg))}
            }
        }
        else
        {
            fail UnsupportedFormatError{Errors.mkString(Format.toString("unsupported type [[%]] for option [[%]]", typeField.name, oneArg))}
        }

        // Set the associated 'isSet' boolean to true
        var addrIsSet = cast([*] bool) &result.isSet
        addrIsSet   += fieldResult.index
        addrIsSet[] = true
    }

    return result
}
