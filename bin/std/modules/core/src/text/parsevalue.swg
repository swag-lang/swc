#global namespace StrConv

using Swag, Core.Errors

// Reject overflow before touching the destination, and return the consumed byte count.
private func(T) storeParsedNumber(destination: *u8, parsed: {value: T, eat: u32, ovf: bool})->u32 fail
{
    if parsed.ovf do
        fail OverflowError{}
    cast(*T, destination)[] = parsed.value
    return parsed.eat
}

// Parses a value of type `type` from the start of `buf` into `addr`, and returns the rest of `buf`.
//
// `addr` must point to initialized storage that can hold a `type`. Accepted types are:
// - `s8`, `s16`, `s32`, `s64`, `u8`, `u16`, `u32`, `u64`, `rune`, `bool`, `f32` and `f64`;
// - [[Core.String]], but not `string`, which would borrow the transient `buf`;
// - an enum, with or without `Swag.EnumFlags`, whose flags are separated by '|';
// - a type that implements [[Core.StrConv.IPokeValue]], which parses its own text;
// - a struct, as a brace-enclosed list of field values in declaration order, such as
//   `{{1 29 27 27} 0}`: a `}` before the last field leaves the remaining fields untouched,
//   and `,` between two values is accepted.
//
// When `type` is a static array or a [[Core.Array]] of those types, `buf` holds several values
// separated with blanks, up to its end or a '#'.
public func parseValue(addr: *void, type: typeinfo, buf: string)->string fail
{
    let patch = cast(*u8, addr)
    var one   = Tokenize.eatSpaces(buf)

    // Dynamic Core.Array
    let valueType = Reflection.dynamicArrayElementType(type)
    if valueType
    {
        let safeValueType = valueType
        while one.count and one[0] != '#'
        {
            let addrVal = Reflection.appendDynamicArrayElement(addr, safeValueType)
            one = try parseValue(addrVal, safeValueType, one)
            one = Tokenize.eatSpaces(one)
        }

        return one
    }

    // Static array
    if Reflection.isStaticArray(type)
    {
        let arrayType = assume cast(const *TypeInfoArray, type)
        var addrVal   = cast([*] u8, addr)
        var cpt       = 0
        while one.count and one[0] != '#'
        {
            if cpt == arrayType.totalCount do
                fail InvalidFormatError{"too many static array values"}
            one     = try parseValue(addrVal, arrayType.finalType, one)
            one     = Tokenize.eatSpaces(one)
            addrVal += arrayType.finalType.sizeof
            cpt     += 1
        }

        return one
    }

    // Enum
    if Reflection.isEnum(type)
    {
        let enumType = assume cast(const *TypeInfoEnum, type)
        let rawType  = enumType.rawType!
        if rawType != string and enumType.sizeof > 8 do
            fail UnsupportedFormatError{Errors.mkString(Format.toString("unsupported enum type [[%]]", rawType.name))}
        let enumFlags = Reflection.hasAttribute(enumType, EnumFlags)

        for
        {
            one = Tokenize.eatSpaces(one)
            let id = try parseIdentifier(one)
            let v  = Reflection.enumValue(type, id)
            if not v do
                fail InvalidFormatError{Errors.mkString(Format.toString("unknown enum value [[%]]", id))}
            let enumValue = v.value!

            if enumType.rawType == string
            {
                cast(*string, patch)[] = cast(const *string, enumValue)[]
            }
            elif not enumFlags
            {
                switch enumType.sizeof
                {
                case 1: cast(*u8, patch)[] = cast(const *u8, enumValue)[]
                case 2: cast(*u16, patch)[] = cast(const *u16, enumValue)[]
                case 4: cast(*u32, patch)[] = cast(const *u32, enumValue)[]
                case 8: cast(*u64, patch)[] = cast(const *u64, enumValue)[]
                }
            }
            else
            {
                switch enumType.sizeof
                {
                case 1: cast(*u8, patch)[] |= cast(const *u8, enumValue)[]
                case 2: cast(*u16, patch)[] |= cast(const *u16, enumValue)[]
                case 4: cast(*u32, patch)[] |= cast(const *u32, enumValue)[]
                case 8: cast(*u64, patch)[] |= cast(const *u64, enumValue)[]
                }
            }

            one = Tokenize.eatCount(one, id.count)
            if not enumFlags do
                break

            one = Tokenize.eatSpaces(one)
            if not one.count do
                break
            if one[0] == '#' do
                break

            if one[0] != '|' do
                fail InvalidFormatError{"invalid enum flags format"}
            one = Tokenize.eatCount(one, 1)
        }

        let eat = cast(u32, cast(s64, (one.buffer - buf.buffer)))
        one = Tokenize.eatCount(buf, cast(u64, eat))
        return one
    }

    // Decode interface
    if let itf = Swag.makeInterface(addr, type, IPokeValue) do
        return try itf.poke(one)

    // Struct: a brace-enclosed list of field values in declaration order. 'Core.String' is
    // excluded because it decodes as a quoted literal below, and a type with a poke interface
    // was already given the whole text above.
    if Reflection.isStruct(type) and type != String
    {
        let structType = assume cast(const *TypeInfoStruct, type)
        if not one.count or one[0] != '{' do
            fail InvalidFormatError{Errors.mkString(Format.toString("missing [[{]] for struct [[%]]", type.name))}
        one = Tokenize.eatCount(one, 1)
        one = Tokenize.eatSpaces(one)

        for field in structType.fields
        {
            if not one.count or one[0] == '}' do
                break
            one = try parseValue(cast([*] u8, addr) + field.offset, field.pointedType!, one)
            one = Tokenize.eatSpaces(one)
            if one.count and one[0] == ','
            {
                one = Tokenize.eatCount(one, 1)
                one = Tokenize.eatSpaces(one)
            }
        }

        if not one.count or one[0] != '}' do
            fail InvalidFormatError{Errors.mkString(Format.toString("missing [[}]] for struct [[%]]", type.name))}
        one = Tokenize.eatCount(one, 1)
        return one
    }

    // Basic types. A native type reaching this function from another module is a
    // different typeinfo instance, so the dispatch reads the native kind instead of
    // switching on typeinfo identity.
    var eat = 0'u32
    if type == String
    {
        eat = try parseString(cast(*String, patch), one)
        return Tokenize.eatCount(one, cast(u64, eat))
    }

    if not Reflection.isNative(type) do
        fail UnsupportedFormatError{Errors.mkString(Format.toString("unsupported type [[%]]", type.name))}

    let nativeType = assume cast(const *TypeInfoNative, type)
    switch nativeType.nativeKind
    {
    case .S8:
        eat = try storeParsedNumber(patch, try parseS8(one))

    case .S16:
        eat = try storeParsedNumber(patch, try parseS16(one))

    case .S32:
        eat = try storeParsedNumber(patch, try parseS32(one))

    case .S64:
        eat = try storeParsedNumber(patch, try parseS64(one))

    case .U8:
        eat = try storeParsedNumber(patch, try parseU8(one))

    case .U16:
        eat = try storeParsedNumber(patch, try parseU16(one))

    case .U32:
        eat = try storeParsedNumber(patch, try parseU32(one))

    case .U64:
        eat = try storeParsedNumber(patch, try parseU64(one))

    case .F32:
        eat = try storeParsedNumber(patch, try parseF32(one))

    case .F64:
        eat = try storeParsedNumber(patch, try parseF64(one))

    case .Bool:
        var val: bool
        {val, eat} = try parseBool(one)
        cast(*bool, patch)[] = val

    case .Rune:
        var val: rune
        {val, eat} = try parseRune(one)
        cast(*rune, patch)[] = val

    default:
        fail UnsupportedFormatError{Errors.mkString(Format.toString("unsupported type [[%]]", type.name))}
    }

    return Tokenize.eatCount(one, cast(u64, eat))
}
