#global namespace StrConv

using Swag, Core.Errors

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
public func parseValue(addr: *void, type: typeinfo, buf: string)->string? fail
{
    let patch = cast(*u8) addr
    var one   = Tokenize.eatSpaces(buf)

    // Dynamic Core.Array
    let valueType = Reflection.dynamicArrayElementType(type)
    if valueType
    {
        let safeValueType = valueType
        while one.count and one[0] != '#'
        {
            let addrVal = Reflection.appendDynamicArrayElement(addr, safeValueType)
            one = (try parseValue(addrVal!, safeValueType, one) orelse "")
            one = Tokenize.eatSpaces(one)
        }

        return one
    }

    // Static array
    if Reflection.isStaticArray(type)
    {
        let arrayType = cast #assume(const *TypeInfoArray) type
        var addrVal   = cast([*] u8) addr
        var cpt       = 0
        while one.count and one[0] != '#'
        {
            if cpt == arrayType.totalCount do
                fail InvalidFormatError{"too many static array values"}
            one     = (try parseValue(addrVal, arrayType.finalType, one) orelse "")
            one     = Tokenize.eatSpaces(one)
            addrVal += arrayType.finalType.sizeof
            cpt     += 1
        }

        return one
    }

    // Enum
    if Reflection.isEnum(type)
    {
        let enumType = cast #assume(const *TypeInfoEnum) type
        let rawType  = enumType.rawType!
        if rawType != string and enumType.sizeof > 8 do
            fail UnsupportedFormatError{Errors.mkString(Format.toString("unsupported enum type [[%]]", rawType.name))}
        let enumFlags = Reflection.hasAttribute(enumType, EnumFlags)

        for
        {
            one = Tokenize.eatSpaces(one)
            let id = try parseIdentifier(one) orelse ""
            let v  = Reflection.enumValue(type, id)
            if not v do
                fail InvalidFormatError{Errors.mkString(Format.toString("unknown enum value [[%]]", id))}
            let enumValue = v.value!

            if enumType.rawType == string
            {
                (cast(*string) patch)[] = (cast(const *string) enumValue)[]
            }
            elif not enumFlags
            {
                switch enumType.sizeof
                {
                case 1: (cast(*u8) patch)[] = (cast(const *u8) enumValue)[]
                case 2: (cast(*u16) patch)[] = (cast(const *u16) enumValue)[]
                case 4: (cast(*u32) patch)[] = (cast(const *u32) enumValue)[]
                case 8: (cast(*u64) patch)[] = (cast(const *u64) enumValue)[]
                }
            }
            else
            {
                switch enumType.sizeof
                {
                case 1: (cast(*u8) patch)[] |= (cast(const *u8) enumValue)[]
                case 2: (cast(*u16) patch)[] |= (cast(const *u16) enumValue)[]
                case 4: (cast(*u32) patch)[] |= (cast(const *u32) enumValue)[]
                case 8: (cast(*u64) patch)[] |= (cast(const *u64) enumValue)[]
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

        let eat = cast(u32) cast(s64) (one.buffer - buf.buffer)
        one = Tokenize.eatCount(buf, cast(u64) eat)
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
        let structType = cast #assume(const *TypeInfoStruct) type
        if not one.count or one[0] != '{' do
            fail InvalidFormatError{Errors.mkString(Format.toString("missing [[{]] for struct [[%]]", type.name))}
        one = Tokenize.eatCount(one, 1)
        one = Tokenize.eatSpaces(one)

        for field in structType.fields
        {
            if not one.count or one[0] == '}' do
                break
            one = (try parseValue(cast([*] u8) addr + field.offset, field.pointedType!, one) orelse "")
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
    var ovf = false
    if type == String
    {
        eat = try parseString(cast(*String) patch, one)
        return Tokenize.eatCount(one, cast(u64) eat)
    }

    if not Reflection.isNative(type) do
        fail UnsupportedFormatError{Errors.mkString(Format.toString("unsupported type [[%]]", type.name))}

    let nativeType = cast #assume(const *TypeInfoNative) type
    switch nativeType.nativeKind
    {
    case .S8:
        var val: s8
        {val, eat, ovf} = try parseS8(one)
        if ovf do
            fail OverflowError{}
        (cast(*s8) patch)[] = val

    case .S16:
        var val: s16
        {val, eat, ovf} = try parseS16(one)
        if ovf do
            fail OverflowError{}
        (cast(*s16) patch)[] = val

    case .S32:
        var val: s32
        {val, eat, ovf} = try parseS32(one)
        if ovf do
            fail OverflowError{}
        (cast(*s32) patch)[] = val

    case .S64:
        var val: s64
        {val, eat, ovf} = try parseS64(one)
        if ovf do
            fail OverflowError{}
        (cast(*s64) patch)[] = val

    case .U8:
        var val: u8
        {val, eat, ovf} = try parseU8(one)
        if ovf do
            fail OverflowError{}
        (cast(*u8) patch)[] = val

    case .U16:
        var val: u16
        {val, eat, ovf} = try parseU16(one)
        if ovf do
            fail OverflowError{}
        (cast(*u16) patch)[] = val

    case .U32:
        var val: u32
        {val, eat, ovf} = try parseU32(one)
        if ovf do
            fail OverflowError{}
        (cast(*u32) patch)[] = val

    case .U64:
        var val: u64
        {val, eat, ovf} = try parseU64(one)
        if ovf do
            fail OverflowError{}
        (cast(*u64) patch)[] = val

    case .F32:
        var val: f32
        {val, eat, ovf} = try parseF32(one)
        if ovf do
            fail OverflowError{}
        (cast(*f32) patch)[] = val

    case .F64:
        var val: f64
        {val, eat, ovf} = try parseF64(one)
        if ovf do
            fail OverflowError{}
        (cast(*f64) patch)[] = val

    case .Bool:
        var val: bool
        {val, eat} = try parseBool(one)
        (cast(*bool) patch)[] = val

    case .Rune:
        var val: rune
        {val, eat} = try parseRune(one)
        (cast(*rune) patch)[] = val

    default:
        fail UnsupportedFormatError{Errors.mkString(Format.toString("unsupported type [[%]]", type.name))}
    }

    return Tokenize.eatCount(one, cast(u64) eat)
}
