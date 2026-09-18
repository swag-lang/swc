#global public
#global namespace StrConv

using Swag, Globalization

// Holds the default formats of the numbers a conversion writes.
struct ConvertFormat
{
    public
    {
        formatInt:   ConvertFormatInt       // Format of integers.
        formatFloat: ConvertFormatFloat     // Format of floating-point numbers.
    }
}

// Describes how a floating-point number is converted to text.
struct ConvertFormatFloat
{
    public
    {
        precision: s8 = -1        // Digits after the decimal point, or -1 for as many as the value needs.
        fmt:       u8 = 'f'u8     // Output format: 'e', 'E', 'f', 'g' or 'G'.
        forceSign: bool           // Whether a positive number also gets a sign.
    }
}

impl ConvertFormatFloat
{
    // Sets the options that the user format `strFormat` specifies, leaving the others unchanged.
    //
    // The format is `[+][fmt][precision]`:
    // + '+'
    //     Forces the sign of a positive number.
    // + 'fmt'
    //     Selects the output format:
    //     | e | -d.dddde±dd, a decimal exponent
    //     | E | -d.ddddE±dd, a decimal exponent
    //     | f | -ddd.dddd, no exponent
    //     | g | 'e' for large exponents, 'f' otherwise
    //     | G | 'E' for large exponents, 'f' otherwise
    // + 'precision'
    //     Sets the number of digits after the decimal point.
    mtd setFormat(strFormat: string?)
    {
        let buffer  = strFormat.buffer
        let countof = strFormat.count
        if buffer == null or countof == 0 do
            return

        var cpt = 0'u32

        // Force sign for positive numbers
        if buffer[cpt] == '+'u8
        {
            .forceSign = true
            cpt        += 1
        }

        // Format
        if cpt < countof
        {
            switch buffer[cpt]
            {
            case 'e'u8, 'E'u8, 'f'u8, 'g'u8, 'G'u8:
                .fmt = buffer[cpt]
                cpt  += 1
            }
        }

        // Precision
        if cpt < countof
        {
            let {userWidth, eatCount, ?} = expect parseU64(Swag.makeString(buffer + cpt, cast(u64) (countof - cpt)))
            Swag.assert(userWidth <= 255, "precision overflow")
            if eatCount do
                .precision = cast(s8) userWidth
        }
    }
}

// Describes how an integer is converted to text.
struct ConvertFormatInt
{
    public
    {
        base:      u32 = 10     // Numeric base, from 2 to 16.
        padding:   u8           // ASCII character that pads the output to `width`, or 0 for none.
        width:     u8           // Minimum width of the padded output, sign included, in characters.
        forceSign: bool         // Whether a positive number also gets a sign.
    }
}

impl ConvertFormatInt
{
    // Sets the options that the user format `strFormat` specifies, leaving the others unchanged.
    //
    // The format is `[+][fmt][padding][width]`:
    // + '+'
    //     Forces the sign of a positive number.
    // + 'fmt'
    //     Selects the output format:
    //     | B | Binary
    //     | D | Decimal
    //     | X | Hexadecimal
    // + 'padding'
    //     Sets the ASCII padding character, which must come before a width.
    // + 'width'
    //     Sets the minimum width of the output, in characters.
    mtd setFormat(strFormat: string?)
    {
        let buffer  = strFormat.buffer
        let countof = strFormat.count
        if buffer == null or countof == 0 do
            return

        var cpt = 0'u32

        // Force sign for positive numbers
        if buffer[cpt] == '+'u8
        {
            .forceSign = true
            cpt        += 1
        }

        // Base
        switch buffer[cpt]
        {
        case 'B'u8:
            .base = 2
            cpt   += 1

        case 'D'u8:
            .base = 10
            cpt   += 1

        case 'X'u8:
            .base = 16
            cpt   += 1
        }

        // Next comes the padding characters
        if cpt >= countof do
            return
        .padding = buffer[cpt]
        cpt      += 1

        // Next comes the padding width
        if cpt >= countof do
            return
        let {userWidth, eatCount, ?} = expect parseU64(Swag.makeString(buffer + cpt, cast(u64) countof - cpt))
        Swag.assert(userWidth <= 255, "padding width overflow")
        if eatCount do
            .width = cast(u8) userWidth
    }
}

// Appends the text of `value` to `buf`, formatted by `convFmt` and the user format `strFormat`.
//
// Numbers follow their format, a pointer is written in hexadecimal, an enum value by name, a
// slice or an array as a bracketed list, and a struct through [[Core.StrConv.convertStruct]].
// A type the conversion does not know is written as '?'.
func convertAny(buf: *ConcatBuffer, value: const any?, convFmt: ConvertFormat, strFormat: string?)
{
    var valueData = value.buffer
    var type      = Reflection.resolveAliases(Swag.kindOf(value))

    // A reference
    if Reflection.isPointerRef(type)
    {
        let ptrType = cast #assume(const *TypeInfoPointer) type
        valueData = (cast(const **void) valueData!)[]
        type      = ptrType.pointedType
    }

    let concreteValue = Swag.makeAny(valueData, type)

    // This is a type
    if Reflection.isType(type)
    {
        let ptrType = (cast(const *(typeinfo?)) valueData!)[]
        if ptrType do
            buf.addBytes(ptrType.fullname)
        else do
            buf.addBytes("null")
        return
    }

    // A pointer, whatever type
    if Reflection.isPointer(type)
    {
        if type.flags & TypeInfoFlags.CString
        {
            let ptr = (cast(const *[*] u8) valueData!)[]
            let len = (cast(cstring?) ptr).count
            buf.addBytes(Swag.makeSlice(ptr, len))
            return
        }

        var fmt: ConvertFormatInt
        fmt.base    = 16
        fmt.width   = 16
        fmt.padding = '0'u8
        fmt.setFormat(strFormat)
        convertInt(buf, (cast(const *u64) valueData!)[], fmt)
        return
    }

    // An enum value
    if Reflection.isEnum(type)
    {
        let enumName = Reflection.enumName(type, valueData)
        if not enumName.isEmpty() do
            buf.addBytes(enumName.toSlice())
        else do
            buf.addBytes("?")
        return
    }

    // A struct
    if Reflection.isStruct(type)
    {
        convertStruct(buf, concreteValue, convFmt, strFormat)
        return
    }

    // A slice
    if Reflection.isSlice(type)
    {
        let ptrSlice = cast #assume(const *TypeInfoSlice) type
        buf.addBytes("[")

        let sl       = cast(const [..] u8?) valueData
        var bufSlice = sl.buffer
        for index in sl.count
        {
            if index do
                buf.addBytes(", ")
            let v = Swag.makeAny(bufSlice, ptrSlice.pointedType)
            convertAny(buf, v, convFmt, strFormat)
            bufSlice += ptrSlice.pointedType.sizeof
        }

        buf.addBytes("]")
        return
    }

    // A static array
    if Reflection.isStaticArray(type)
    {
        let ptrArr = cast #assume(const *TypeInfoArray) type
        var bufArr = cast(const [*] u8?) valueData

        buf.addBytes("[")
        for index in ptrArr.count
        {
            if index do
                buf.addBytes(", ")
            let v = Swag.makeAny(bufArr, ptrArr.pointedType)
            convertAny(buf, v, convFmt, strFormat)
            bufArr += ptrArr.pointedType.sizeof
        }

        buf.addBytes("]")
        return
    }

    if Reflection.isInteger(type)
    {
        convertIntAny(buf, concreteValue, convFmt, strFormat)
        return
    }

    if Reflection.isFloat(type)
    {
        convertFloatAny(buf, concreteValue, convFmt, strFormat)
        return
    }

    // Any
    if Reflection.isAny(type)
    {
        let ptrAny = cast(const * (any?)) valueData!
        buf.addBytes("{type = ")
        let typeAny = Swag.kindOf(ptrAny[])
        convertAny(buf, typeAny, convFmt, strFormat)
        buf.addBytes(", value = ")
        if (ptrAny[]).buffer do
            convertAny(buf, ptrAny[]!, convFmt, strFormat)
        else do
            buf.addBytes("null")
        buf.addBytes("}")
        return
    }

    // `const any` keeps qualifiers on native payload types, so exact typeinfo
    // matching is too strict here. Switch on the native kind instead.
    if Reflection.isNative(type)
    {
        let typeNative = cast #assume(const *TypeInfoNative) type
        switch typeNative.nativeKind
        {
        case .Bool:
            convertBool(buf, (cast(const *bool) valueData!)[])
            return

        case .Rune:
            convertRune(buf, (cast(const *rune) valueData!)[])
            return

        case .String:
            buf.addBytes((cast(const *string) valueData!)[])
            return
        }
    }

    buf.addBytes("?")
}

// Appends the text of the struct `value` to `buf`.
//
// A [[Core.String]] is written as is, a struct that implements [[Core.StrConv.IConvert]] writes
// itself, and any other struct is written as `{field = value, ...}`.
func convertStruct(buf: *ConcatBuffer, value: const any?, convFmt: ConvertFormat, strFormat: string?)
{
    let kindof = cast #assume(const *Swag.TypeInfoStruct) Swag.kindOf(value)
    Swag.assert(kindof.kind == TypeInfoKind.Struct, "this is not a structure")
    let ptr = cast(const [*] u8?) value.buffer

    // Core.String
    if kindof == String
    {
        let ptrStr = cast(const *String) ptr!
        buf.addBytes(ptrStr.toSlice())
        return
    }

    // A structure with an implementation of IConvert
    if let itf = Swag.makeInterface(ptr, kindof, IConvert)
    {
        itf.convert(buf, convFmt, strFormat)
        return
    }

    // Do it field by field
    buf.addBytes("{")
    for field, index in kindof.fields
    {
        if index do
            buf.addBytes(", ")
        buf.addBytes(field.name)
        buf.addBytes(" = ")
        let val = Swag.makeAny(ptr + field.offset, field.pointedType)
        convertAny(buf, val, convFmt, strFormat)
    }

    buf.addBytes("}")
}

// Appends the text of the floating-point `value` to `buf`, formatted by `fmt`.
func convertFloat(buf: *ConcatBuffer, value: const any?, fmt: ConvertFormatFloat)
{
    let kindof = cast #assume(const *Swag.TypeInfoNative) Swag.kindOf(value)
    Swag.assert(kindof.flags & TypeInfoFlags.Float != 0, "value to convert is not a float")

    let dataof = value.buffer

    var value64: f64
    switch kindof.nativeKind
    {
    case .F32: value64 = cast(f64) (cast(const *f32) dataof!)[]
    case .F64: value64 = (cast(const *f64) dataof!)[]
    }

    Dtoa.append(buf, value64, fmt.fmt, cast(s64) fmt.precision, fmt.forceSign)
}

// Appends the text of the integer `value` to `buf`, formatted by `fmt`.
func convertInt(buf: *ConcatBuffer, value: const any?, fmt: ConvertFormatInt)
{
    let kindof = cast #assume(const *Swag.TypeInfoNative) Swag.kindOf(value)
    Swag.assert(kindof.flags & TypeInfoFlags.Integer != 0, "value to convert is not an integer")
    Swag.assert(0 < fmt.base and fmt.base <= 16, "invalid convert base")

    let dataof = value.buffer
    var bits   = kindof.sizeof * 8

    var value64:     u64
    var signedValue: s64

    var overflowS64 = false
    switch kindof.nativeKind
    {
    case .S8:
        signedValue = cast(s64) (cast(const *s8) dataof!)[]
        value64     = cast(u64) Math.abs(signedValue)

    case .S16:
        signedValue = cast(s64) (cast(const *s16) dataof!)[]
        value64     = cast(u64) Math.abs(signedValue)

    case .S32:
        signedValue = cast(s64) (cast(const *s32) dataof!)[]
        value64     = cast(u64) Math.abs(signedValue)

    case .S64:
        signedValue = (cast(const *s64) dataof!)[]
        if signedValue == Swag.S64.Min do
            overflowS64 = true
        else do
            value64 = cast(u64) Math.abs(signedValue)

    case .U8:
        value64 = cast(u64) (cast(const *u8) dataof!)[]

    case .U16:
        value64 = cast(u64) (cast(const *u16) dataof!)[]

    case .U32:
        value64 = cast(u64) (cast(const *u32) dataof!)[]

    case .U64:
        value64 = (cast(const *u64) dataof!)[]
    }

    const Tbl = "0123456789ABCDEF"
    var tmp: [64] u8
    var cpt = 63'u32

    // Special case for the lower digit of Swag.S64.Min
    // We have 9_223_372_036_854_775_807, and we want -9_223_372_036_854_775_808
    // So use '8' instead of '7'
    if overflowS64
    {
        let c = Tbl[8 % fmt.base]
        tmp[cpt]  = c
        cpt, bits -= 1
        switch fmt.base
        {
        case 2:  value64 = 4611686018427387904
        case 10: value64 = 922337203685477580
        case 16: value64 = 576460752303423488
        }
    }

    for bits
    {
        let c = Tbl[value64 % fmt.base]
        tmp[cpt] = c
        cpt      -= 1
        value64  /= cast(u64) fmt.base
        if not value64 do
            break
    }

    // Fill the remaining place with the padding character, so that the total result,
    // including an eventual sign, is 'fmt.width' long.
    if fmt.padding
    {
        let signWidth = signedValue < 0 or fmt.forceSign ? 1'u32 : 0'u32
        var curWidth  = 63 - cpt
        while curWidth < fmt.width and cpt > 1
        {
            if curWidth + signWidth >= fmt.width do
                break
            tmp[cpt] = fmt.padding
            curWidth += 1
            cpt      -= 1
        }
    }

    // Prepend the negative character
    if signedValue < 0
    {
        tmp[cpt] = cast(u8) g_CultureInfo.numberFormat.negativeSign
        cpt      -= 1
    }
    elif fmt.forceSign
    {
        tmp[cpt] = cast(u8) g_CultureInfo.numberFormat.positiveSign
        cpt      -= 1
    }

    buf.addBytes(tmp[cpt + 1 to])
}

// Appends the text of the floating-point `value` to `buf`, formatted by `convFmt` and the user format `strFormat`.
func convertFloatAny(buf: *ConcatBuffer, value: const any?, convFmt: ConvertFormat, strFormat: string?)
{
    Swag.assert(Swag.kindOf(value).flags & TypeInfoFlags.Float != 0, "value to convert is not a float")

    var fmt = convFmt.formatFloat
    fmt.setFormat(strFormat)
    convertFloat(buf, value, fmt)
}

// Appends the text of the integer `value` to `buf`, formatted by `convFmt` and the user format `strFormat`.
func convertIntAny(buf: *ConcatBuffer, value: const any?, convFmt: ConvertFormat, strFormat: string?)
{
    Swag.assert(Swag.kindOf(value).flags & TypeInfoFlags.Integer != 0, "value to convert is not an integer")

    var fmt = convFmt.formatInt
    fmt.setFormat(strFormat)
    convertInt(buf, value, fmt)
}

// Appends `true` or `false` to `buf`.
func convertBool(buf: *ConcatBuffer, value: bool)
{
    buf.addBytes(value ? "true" : "false")
}

// Appends the UTF-8 encoding of `value` to `buf`, or '?' for the zero rune.
func convertRune(buf: *ConcatBuffer, value: rune)
{
    var arr: [4] u8
    if not value do
        buf.addBytes("?")
    else
    {
        let count = Utf8.encodeRune(arr, value)
        buf.addBytes(arr[until count])
    }
}

// Appends the text of `value` to `buf`, choosing the conversion from the type `T` at compile time.
//
// An integer or a floating-point number uses its default format overridden by `strFormat`, and
// ignores `convFmt`. Other types go through [[Core.StrConv.convertAny]].
func(T) convert(buf: *ConcatBuffer, value: T, convFmt: ConvertFormat, strFormat: string?)
{
    #static if Reflection.isInteger(T)
    {
        var fmt: ConvertFormatInt
        fmt.setFormat(strFormat)
        convertInt(buf, value, fmt)
    }
    elif Reflection.isFloat(T)
    {
        var fmt: ConvertFormatFloat
        fmt.setFormat(strFormat)
        convertFloat(buf, value, fmt)
    }
    elif Reflection.isBool(T)
    {
        convertBool(buf, value)
    }
    elif Reflection.isRune(T)
    {
        convertRune(buf, value)
    }
    elif Reflection.isString(T)
    {
        buf.addBytes(value)
    }
    else
    {
        convertAny(buf, value, convFmt, strFormat)
    }
}
