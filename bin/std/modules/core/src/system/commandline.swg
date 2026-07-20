#global export
#global namespace CommandLine
using Core.Errors

attr ArgParams(nameAlias: #null string = null)

struct ParseOptions {}

// The 'IsSet' generic struct is a mirror of the user input struct.
//
// Each field has the same name as the original one, but with a 'bool' type.
//
// It will indicate, after the command line parsing, that the corresponding argument has been
// specified or not by the user.
struct(T) IsSet
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

// Result of the [parse] function
struct(T) Result
{
    isSet: IsSet'T
}

// Returns true if 'oneArg' is a valid option (starting with a delimiter)
func isOption(oneArg: #nonull string, _options: ParseOptions)->bool
{
    if @countof(oneArg) == 0 do
        return false
    return oneArg[0] == '-'
}

func isValue(oneArg: #nonull string, typeField: #nonull typeinfo, options: ParseOptions)->bool
{
    if !isOption(oneArg, options) do
        return true

    let concreteType = Reflection.makeConcreteAlias(typeField)

    if !Reflection.isInteger(concreteType) and !Reflection.isFloat(concreteType) do
        return false

    if @countof(oneArg) < 2 do
        return false
    if !Latin1.isDigit(oneArg[1])
    {
        if !Reflection.isFloat(concreteType) do
            return false
        if oneArg[1] != '.''u8 or @countof(oneArg) < 3 or !Latin1.isDigit(oneArg[2]) do
            return false
    }

    return true
}

private struct SplitArgument
{
    value:         #nonull string
    attachedValue: bool
}

private func splitArgumentsEx(args: #nonull const [..] #nonull string, options: ParseOptions)->Array'SplitArgument
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
            allArgs.add(SplitArgument{value: oneArg})
            continue
        }

        let split = Tokenize.splitAny(oneArg, [':''rune, '=''rune], 1)
        if split.count == 2
        {
            let name = Latin1.trim(split[0])
            allArgs.add(SplitArgument{value: name})
            let other = Latin1.trim(split[1])
            if @countof(other) do
                allArgs.add(SplitArgument{value: other, attachedValue: true})
        }
        else
        {
            allArgs.add(SplitArgument{value: oneArg})
        }
    }

    return allArgs
}

// Clean and split a list of arguments
// -option:value or -option=value => -option value
func splitArguments(args: #nonull const [..] #nonull string, options: ParseOptions)->Array'(#nonull string)
{
    var allArgs: retval

    for it in splitArgumentsEx(args, options)
    {
        allArgs.add(it.value)
    }

    return allArgs
}

struct FieldResult
{
    field: #null const *Swag.TypeValue
    index: u64 = Swag.U64.Max
}

func getField(typeStruct: #nonull const *Swag.TypeInfoStruct, name: #nonull string)->FieldResult
{
    var result: retval

    for &it in typeStruct.fields
    {
        // Test normal name (field)
        if it.name == name
        {
            result.field = it
            result.index = @index
            return result
        }

        // Test name alias
        let aliasName = Reflection.getAttributeValue(it, ArgParams, "nameAlias", cast(#null string) null)
        if aliasName == name
        {
            result.field = it
            result.index = @index
            return result
        }
    }

    return result
}

// Parse all the arguments and fill the result
func(T) parse(st: #nonull *T, args: #nonull const [..] #nonull string, options = ParseOptions{})->Result throw
{
#[Swag.Mixin]
    func checkNext(typeField: #nonull typeinfo) throw
    {
        if itp + 1 == maxItp do
            throw SyntaxError{Errors.mkString(Format.toString("missing value for option [[%]]", oneArg))}

        let nextArg = allArgs[itp + 1]
        if !nextArg.attachedValue and !isValue(nextArg.value, typeField, options) do
            throw SyntaxError{Errors.mkString(Format.toString("missing value for option [[%]]", oneArg))}
    }

    var result: retval

    // First pass
    let allArgs = splitArgumentsEx(args, options)

    // Parse all
    let typeof = #typeof(T)
    let maxItp = @countof(allArgs)
    for var itp = 0; itp < maxItp; itp += 1
    {
        var oneArg = allArgs[itp].value
        if !isOption(oneArg, options) do
            throw SyntaxError{Errors.mkString(Format.toString("invalid option [[%]]", oneArg))}

        oneArg = Tokenize.eatCount(oneArg, 1)

        let fieldResult = getField(typeof, oneArg)
        let typeParam   = fieldResult.field
        if !typeParam do
            throw SyntaxError{Errors.mkString(Format.toString("unknown option [[%]]", oneArg))}

        let field = typeParam orelse cast(#nonull const *Swag.TypeValue) 1'u64
        let typeField = field.pointedType orelse #typeof(u8)

        var addr = cast(#nonull [*] u8) st
        addr += field.offset

        // Bool: Result is true if the option does not have an associated value
        if Reflection.isBool(typeField) and
           (itp + 1 == maxItp or isOption(allArgs[itp + 1].value, options))
        {
            dref cast(#nonull *bool) addr = true
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
            let rest = catch StrConv.parseValue(addr, typeField, allArgs[itp + 1].value)
            itp += 1

            if @err != null do
                throw SyntaxError{Errors.mkString(Format.toString("invalid value for option [[%]]", oneArg))}
            if @countof(rest) do
                throw SyntaxError{Errors.mkString(Format.toString("invalid value for option [[%]]", oneArg))}
        }

        // Dynamic array of values
        elif Reflection.isStructArray(typeField)
        {
            let arrayType = Reflection.getStructArrayType(typeField) orelse #typeof(u8)
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

            if collect != null do
                discard catch StrConv.parseValue(addr, typeField, collect.toString())
            if @err != null do
                throw SyntaxError{Errors.mkString(Format.toString("invalid value for option [[%]]", oneArg))}
        }
        else
        {
            throw UnsupportedFormatError{Errors.mkString(Format.toString("unsupported type [[%]] for option [[%]]", typeField.name, oneArg))}
        }

        // Set the associated 'isSet' boolean to true
        var addrIsSet = cast(#nonull [*] bool) &result.isSet
        addrIsSet += fieldResult.index
        dref addrIsSet = true
    }

    return result
}
