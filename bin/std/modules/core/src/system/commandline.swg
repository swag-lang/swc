#global export
#global namespace CommandLine
using Core.Errors

attr ArgParams(nameAlias: string = null)

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
        foreach f in typeof.fields do
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
func isOption(oneArg: string, _options: ParseOptions)->bool
{
    if @countof(oneArg) == 0 do
        return false
    return oneArg[0] == '-'
}

func isValue(oneArg: string, typeField: typeinfo, options: ParseOptions)->bool
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

// Clean and split a list of arguments
// -option:value or -option=value => -option value
func splitArguments(args: const [..] string, options: ParseOptions)->Array'string
{
    var allArgs: retval

    // Clean all arguments
    foreach it in args
    {
        var oneArg = it
        oneArg = Latin1.trim(oneArg)
        if !@countof(oneArg) do
            continue

        if !isOption(oneArg, options)
        {
            allArgs.add(oneArg)
            continue
        }

        let split = Tokenize.splitAny(oneArg, [':''rune, '=''rune], 1)
        if split.count == 2
        {
            let name = Latin1.trim(split[0])
            allArgs.add(name)
            let other = Latin1.trim(split[1])
            if @countof(other) do
                allArgs.add(other)
        }
        else
        {
            allArgs.add(oneArg)
        }
    }

    return allArgs
}

struct FieldResult
{
    field: #null const *Swag.TypeValue
    index: u64 = Swag.U64.Max
}

func getField(typeStruct: const *Swag.TypeInfoStruct, name: string)->FieldResult
{
    var result: retval

    foreach it in typeStruct.fields
    {
        // Test normal name (field)
        if it.name == name
        {
            result.field = it
            result.index = @index
            return result
        }

        // Test name alias
        let value = Reflection.getAttributeValue(it, ArgParams, "nameAlias")
        if @dataof(value) and Reflection.isString(@kindof(value)) and cast(string) value == name
        {
            result.field = it
            result.index = @index
            return result
        }
    }

    return result
}

// Parse all the arguments and fill the result
func(T) parse(st: *T, args: const [..] string, options = CommandLine.ParseOptions{})->Result throw
{
#[Swag.Mixin]
    func checkNext(typeField: typeinfo) throw
    {
        if itp + 1 == maxItp or !isValue(allArgs[itp + 1], typeField, options) do
            throw SyntaxError{Errors.mkString(Format.toString("missing value for option [[%]]", oneArg))}
    }

    var result: retval

    // First pass
    let allArgs = splitArguments(args, options)

    // Parse all
    let typeof = #typeof(T)
    let maxItp = @countof(allArgs)
    for var itp = 0; itp < maxItp; itp += 1
    {
        var oneArg = allArgs[itp]
        if !isOption(oneArg, options) do
            throw SyntaxError{Errors.mkString(Format.toString("invalid option [[%]]", oneArg))}

        oneArg = Tokenize.eatCount(oneArg, 1)

        let fieldResult = getField(typeof, oneArg)
        let typeParam   = fieldResult.field
        if !typeParam do
            throw SyntaxError{Errors.mkString(Format.toString("unknown option [[%]]", oneArg))}

        let typeField = typeParam.pointedType

        var addr = cast([*] u8) st
        addr += typeParam.offset

        // Bool: Result is true if the option does not have an associated value
        if Reflection.isBool(typeField) and
           (itp + 1 == maxItp or isOption(allArgs[itp + 1], options))
        {
            dref cast(*bool) addr = true
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
            let rest = catch StrConv.parseValue(addr, typeField, allArgs[itp + 1])
            itp += 1

            if @err != null do
                throw SyntaxError{Errors.mkString(Format.toString("invalid value for option [[%]]", oneArg))}
            if @countof(rest) do
                throw SyntaxError{Errors.mkString(Format.toString("invalid value for option [[%]]", oneArg))}
        }

        // Dynamic array of values
        elif Reflection.isStructArray(typeField)
        {
            let arrayType = Reflection.getStructArrayType(typeField)
            try checkNext(arrayType)

            // If it's an array of strings, we will need to add string delimiters
            // to each value
            let isString = arrayType == Core.String

            // Make one single string with all values, for pokeValue
            var collect: String
            while itp + 1 != maxItp and isValue(allArgs[itp + 1], arrayType, options)
            {
                var other = allArgs[itp + 1]
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
        var addrIsSet = cast([*] bool) &result.isSet
        addrIsSet += fieldResult.index
        dref addrIsSet = true
    }

    return result
}
