#global public
#global namespace StrConv

using Globalization, Swag, Errors

// Parses the hexadecimal digits at the start of `str` as an unsigned integer.
//
// Returns the value, the number of bytes consumed in `eat`, and `ovf` set when the value does not
// fit in a `u64`; the remaining digits are consumed all the same. Fails with
// [[Core.Errors.SyntaxError]] when `str` does not start with a hexadecimal digit.
func parseX64(str: string)->{ value: u64, eat: u32, ovf: bool } fail
{
    var result: retval

    let countof = str.count
    if not countof do
        fail SyntaxError{}

    var buffer = str.buffer
    var cpt    = 0'u32
    var value  = 0'u64

    if not Latin1.isHexDigit(buffer[]) do
        fail SyntaxError{}
    while cpt < countof and Latin1.isHexDigit(buffer[])
    {
        if value & 0xF0000000_00000000
        {
            result.ovf = true
        }
        else
        {
            value <<= 4
            let c = buffer[]
            if Latin1.isDigit(c) do
                value += cast(u64) (c - '0'u8)
            elif c <= 'F'u8 do
                value += 10'u64 + (c - 'A'u8)
            else do
                value += 10'u64 + (c - 'a'u8)
        }

        buffer, cpt += 1
    }

    result.value = value
    result.eat   = cpt
    return result
}

// Parses the binary digits at the start of `str` as an unsigned integer.
//
// Returns the value, the number of bytes consumed in `eat`, and `ovf` set when the value does not
// fit in a `u64`; the remaining digits are consumed all the same. Fails with
// [[Core.Errors.SyntaxError]] when `str` does not start with '0' or '1'.
func parseB64(str: string)->{ value: u64, eat: u32, ovf: bool } fail
{
    var result: retval

    let countof = str.count
    if not countof do
        fail SyntaxError{}

    var buffer = str.buffer
    var cpt    = 0'u32
    var value  = 0'u64

    if not Latin1.isBinDigit(buffer[]) do
        fail SyntaxError{}
    while cpt < countof and Latin1.isBinDigit(buffer[])
    {
        if value & 0x80000000_00000000
        {
            result.ovf = true
        }
        else
        {
            value <<= 1
            value += cast(u64) (buffer[] - '0'u8)
        }

        buffer, cpt += 1
    }

    result.value = value
    result.eat   = cpt
    return result
}

// Parses the unsigned integer at the start of `str` as a `u8`, like [[Core.StrConv.parseU64]].
//
// A value above `Swag.U8.Max` saturates to it and sets `ovf`.
func parseU8(str: string)->{ value: u8, eat: u32, ovf: bool } fail
{
    let {res, eat, ovf} = try parseU64(str)
    if res > Swag.U8.Max do
        return {Swag.U8.Max, eat, true}
    return {cast(u8) res, eat, ovf}
}

// Parses the unsigned integer at the start of `str` as a `u16`, like [[Core.StrConv.parseU64]].
//
// A value above `Swag.U16.Max` saturates to it and sets `ovf`.
func parseU16(str: string)->{ value: u16, eat: u32, ovf: bool } fail
{
    let {res, eat, ovf} = try parseU64(str)
    if res > Swag.U16.Max do
        return {Swag.U16.Max, eat, true}
    return {cast(u16) res, eat, ovf}
}

// Parses the unsigned integer at the start of `str` as a `u32`, like [[Core.StrConv.parseU64]].
//
// A value above `Swag.U32.Max` saturates to it and sets `ovf`.
func parseU32(str: string)->{ value: u32, eat: u32, ovf: bool } fail
{
    let {res, eat, ovf} = try parseU64(str)
    if res > Swag.U32.Max do
        return {Swag.U32.Max, eat, true}
    return {cast(u32) res, eat, ovf}
}

// Parses the unsigned integer at the start of `str`.
//
// Accepts decimal digits, or a `0x` or `0b` prefix followed by hexadecimal or binary digits.
// Returns the value, the number of bytes consumed in `eat`, and `ovf` set when the value does not
// fit in a `u64`. Fails with [[Core.Errors.SyntaxError]] when `str` does not start with a digit.
func parseU64(str: string)->{ value: u64, eat: u32, ovf: bool } fail
{
    var result: retval

    let countof = str.count
    if not countof do
        fail SyntaxError{}

    // Detect 0x for hexadecimal, 0b for binary.
    if countof > 2 and str[0] == '0'u8
    {
        let c = str[1] | 32
        if c == 'x'u8
        {
            {result.value, result.eat, result.ovf} = try parseX64(str[2 to])
            result.eat += 2
            return result
        }

        if c == 'b'u8
        {
            {result.value, result.eat, result.ovf} = try parseB64(str[2 to])
            result.eat += 2
            return result
        }
    }

    var buffer = str.buffer
    var cpt    = 0'u32
    var value  = 0'u64

    if not Latin1.isDigit(buffer[]) do
        fail SyntaxError{}
    while cpt < countof and Latin1.isDigit(buffer[])
    {
        let value1 = value * #wrap 10
        if value1 < value
        {
            result.ovf = true
            value      = Swag.U64.Max
        }
        else do
            value = value1

        if not result.ovf
        {
            let add = cast(u64) (buffer[] - '0'u8)
            if value + #wrap add < value
            {
                result.ovf = true
                value      = Swag.U64.Max
            }
            else do
                value += add
        }

        buffer, cpt += 1
    }

    result.value = value
    result.eat   = cpt
    return result
}

// Parses the signed decimal integer at the start of `str` as an `s8`, like [[Core.StrConv.parseS64]].
//
// A value outside the `s8` range saturates to the nearest bound and sets `ovf`.
func parseS8(str: string)->{ value: s8, eat: u32, ovf: bool } fail
{
    let {res, eat, ovf} = try parseS64(str)
    if res < Swag.S8.Min do
        return {Swag.S8.Min, eat, true}
    if res > Swag.S8.Max do
        return {Swag.S8.Max, eat, true}
    return {cast(s8) res, eat, ovf}
}

// Parses the signed decimal integer at the start of `str` as an `s16`, like [[Core.StrConv.parseS64]].
//
// A value outside the `s16` range saturates to the nearest bound and sets `ovf`.
func parseS16(str: string)->{ value: s16, eat: u32, ovf: bool } fail
{
    let {res, eat, ovf} = try parseS64(str)
    if res < Swag.S16.Min do
        return {Swag.S16.Min, eat, true}
    if res > Swag.S16.Max do
        return {Swag.S16.Max, eat, true}
    return {cast(s16) res, eat, ovf}
}

// Parses the signed decimal integer at the start of `str` as an `s32`, like [[Core.StrConv.parseS64]].
//
// A value outside the `s32` range saturates to the nearest bound and sets `ovf`.
func parseS32(str: string)->{ value: s32, eat: u32, ovf: bool } fail
{
    let {res, eat, ovf} = try parseS64(str)
    if res < Swag.S32.Min do
        return {Swag.S32.Min, eat, true}
    if res > Swag.S32.Max do
        return {Swag.S32.Max, eat, true}
    return {cast(s32) res, eat, ovf}
}

// Parses the signed decimal integer at the start of `str`.
//
// An optional leading sign is spelled as in the current culture's number format. Returns the
// value, the number of bytes consumed in `eat`, and `ovf` set when the value does not fit in an
// `s64`. Fails with [[Core.Errors.ParseIncompleteError]] when `str` holds only a sign, and with
// [[Core.Errors.SyntaxError]] when no digit follows.
func parseS64(str: string)->{ value: s64, eat: u32, ovf: bool } fail
{
    var result: retval

    let countof = str.count
    if not countof do
        fail SyntaxError{}

    var buffer = str.buffer
    var value  = 0'u64
    var cpt    = 0'u32

    // An optional sign comes first.
    var signed   = false
    let c        = str[0]
    var maxValue = cast(u64) Swag.S64.Max
    if c == g_CultureInfo.numberFormat.negativeSign
    {
        buffer, cpt += 1
        signed      = true
        maxValue    += 1
        if cpt == countof do
            fail ParseIncompleteError{}
    }
    elif c == g_CultureInfo.numberFormat.positiveSign
    {
        buffer, cpt += 1
        if cpt == countof do
            fail ParseIncompleteError{}
    }

    // Parse the rest.
    if not Latin1.isDigit(buffer[]) do
        fail SyntaxError{}
    while cpt < countof and Latin1.isDigit(buffer[])
    {
        let value1 = value * #wrap 10
        if value1 < value
        {
            result.ovf = true
            value      = Swag.U64.Max
        }
        else do
            value = value1

        if not result.ovf
        {
            let toAdd = cast(u64) (buffer[] - '0'u8)
            if value + toAdd > maxValue
            {
                result.ovf = true
                value      = maxValue
            }
            else do
                value += toAdd
        }

        buffer, cpt += 1
    }

    if not result.ovf
    {
        if signed
        {
            if value == maxValue do
                result.value = Swag.S64.Min
            else do
                result.value = -cast(s64) value
        }
        else do
            result.value = cast(s64) value
    }

    result.eat = cpt
    return result
}

// Parses the floating-point number at the start of `str` as an `f32`, like [[Core.StrConv.parseF64]].
//
// A nonzero magnitude below `Swag.F32.Min` or above `Swag.F32.Max` saturates to that bound and
// sets `ovf`.
func parseF32(str: string)->{ value: f32, eat: u32, ovf: bool } fail
{
    let {res, eat, ovf} = try parseF64(str)
    let absRes = Math.abs(res)
    if absRes != 0 and absRes < Swag.F32.Min
    {
        if res < 0 do
            return {-Swag.F32.Min, eat, true}
        return {Swag.F32.Min, eat, true}
    }

    if absRes > Swag.F32.Max
    {
        if res < 0 do
            return {-Swag.F32.Max, eat, true}
        return {Swag.F32.Max, eat, true}
    }

    return {cast(f32) res, eat, ovf}
}

// Parses the floating-point number at the start of `str`.
//
// Returns the value, the number of bytes consumed in `eat`, and `ovf` set when the value does not
// fit in an `f64`. Signs and the decimal separator are spelled as in the current culture's number
// format.
func parseF64(str: string)->{ value: f64, eat: u32, ovf: bool } fail => try StrConv.Atod.parse(str)

// Parses the boolean word at the start of `str`.
//
// Accepts `1`, `true`, `TRUE` and `True` for true, and `0`, `false`, `FALSE` and `False` for
// false. Returns the value and the number of bytes consumed in `eat`. Fails with
// [[Core.Errors.SyntaxError]] for any other word.
func parseBool(str: string)->{ value: bool, eat: u32 } fail
{
    var result: retval

    let sub = Tokenize.alphanumericPrefix(str)
    switch sub
    {
    case "1", "true", "TRUE", "True":    result.value = true
    case "0", "false", "FALSE", "False": result.value = false
    default: fail SyntaxError{}
    }

    result.eat = cast(u32) sub.count
    return result
}

// Decodes the rune at the start of `str` and returns it with the number of bytes it occupies.
//
// An invalid sequence returns [[Core.Utf8.RuneError]] with `eat` 1. Fails with
// [[Core.Errors.SyntaxError]] when `str` is empty.
func parseRune(str: string)->{ value: rune, eat: u32 } fail
{
    let countof = str.count
    if not countof do
        fail SyntaxError{}
    return Utf8.decodeRune(str)
}

// Returns the identifier at the start of `str`.
//
// An identifier starts with '_' or a letter and continues with '_', letters and digits, each byte
// classified by [[Core.Latin1.isLetter]] and [[Core.Latin1.isLetterOrDigit]]. Fails with
// [[Core.Errors.SyntaxError]] when `str` does not start with one.
func parseIdentifier(str: string)->string? fail
{
    let countof = str.count
    if not countof do
        fail SyntaxError{}

    if str[0] != '_'u8 and not Latin1.isLetter(str[0]) do
        fail SyntaxError{}

    var cpt = 1'u64
    while cpt < countof and (str[cpt] == '_'u8 or Latin1.isLetterOrDigit(str[cpt])) do
        cpt += 1
    return str[until cpt]
}

// Parses the text at the start of `str` into `result` and returns the number of bytes consumed.
//
// Text that starts with '"' ends at the next '"', and neither quote is stored; other text runs to
// the end of `str`. Fails with [[Core.Errors.SyntaxError]] when `str` is empty, and with
// [[Core.Errors.ParseIncompleteError]] when the closing quote is missing.
func parseString(result: *String, str: string)->u32 fail
{
    let countof = str.count
    if not countof do
        fail SyntaxError{}

    result.clear()

    var isQuoted = false
    var cpt      = 0
    if str[0] == '"'u8
    {
        isQuoted = true
        cpt      += 1
    }

    while cpt < countof
    {
        // End delimiter.
        if str[cpt] == '"'u8 and isQuoted do
            break

        // Escape character.
        if str[cpt] == '\\'u8
        {
            cpt += 1
            if cpt == countof do
                fail SyntaxError{}
            switch str[cpt]
            {
            case 't'u8: result[] += '\t'u8
            case 'n'u8: result[] += '\n'u8
            default:    result[] += str[cpt]
            }
        }
        else do
            result[] += str[cpt]

        cpt += 1
    }

    if cpt == countof and isQuoted do
        fail ParseIncompleteError{}
    if isQuoted do
        cpt += 1
    return cast(u32) cpt
}

// Parses the text at the start of `str` and returns it with the number of bytes consumed.
//
// The rules are those of the overload that fills a caller's [[Core.String]].
func parseString(str: string)->{ value: String, eat: u32 } fail
{
    var result: retval
    result.eat = try parseString(&result.value, str)
    return result
}

// Converts the whole of `str` to an `s8`.
//
// Fails with [[Core.Errors.OverflowError]] when the value does not fit, and with
// [[Core.Errors.SyntaxError]] when `str` holds anything after the number.
func toS8(str: string)->s8 fail
{
    let {v, eat, ovf} = try parseS8(str)
    if ovf do
        fail OverflowError{}
    if eat != str.count do
        fail SyntaxError{}
    return v
}

// Converts the whole of `str` to an `s16`, like [[Core.StrConv.toS8]].
func toS16(str: string)->s16 fail
{
    let {v, eat, ovf} = try parseS16(str)
    if ovf do
        fail OverflowError{}
    if eat != str.count do
        fail SyntaxError{}
    return v
}

// Converts the whole of `str` to an `s32`, like [[Core.StrConv.toS8]].
func toS32(str: string)->s32 fail
{
    let {v, eat, ovf} = try parseS32(str)
    if ovf do
        fail OverflowError{}
    if eat != str.count do
        fail SyntaxError{}
    return v
}

// Converts the whole of `str` to an `s64`, like [[Core.StrConv.toS8]].
func toS64(str: string)->s64 fail
{
    let {v, eat, ovf} = try parseS64(str)
    if ovf do
        fail OverflowError{}
    if eat != str.count do
        fail SyntaxError{}
    return v
}

// Converts the whole of `str` to a `u8`, like [[Core.StrConv.toS8]].
func toU8(str: string)->u8 fail
{
    let {v, eat, ovf} = try parseU8(str)
    if ovf do
        fail OverflowError{}
    if eat != str.count do
        fail SyntaxError{}
    return v
}

// Converts the whole of `str` to a `u16`, like [[Core.StrConv.toS8]].
func toU16(str: string)->u16 fail
{
    let {v, eat, ovf} = try parseU16(str)
    if ovf do
        fail OverflowError{}
    if eat != str.count do
        fail SyntaxError{}
    return v
}

// Converts the whole of `str` to a `u32`, like [[Core.StrConv.toS8]].
func toU32(str: string)->u32 fail
{
    let {v, eat, ovf} = try parseU32(str)
    if ovf do
        fail OverflowError{}
    if eat != str.count do
        fail SyntaxError{}
    return v
}

// Converts the whole of `str` to a `u64`, like [[Core.StrConv.toS8]].
func toU64(str: string)->u64 fail
{
    let {v, eat, ovf} = try parseU64(str)
    if ovf do
        fail OverflowError{}
    if eat != str.count do
        fail SyntaxError{}
    return v
}

// Converts the whole of `str` to an `f32`, like [[Core.StrConv.toS8]].
func toF32(str: string)->f32 fail
{
    let {v, eat, ovf} = try parseF32(str)
    if ovf do
        fail OverflowError{}
    if eat != str.count do
        fail SyntaxError{}
    return v
}

// Converts the whole of `str` to an `f64`, like [[Core.StrConv.toS8]].
func toF64(str: string)->f64 fail
{
    let {v, eat, ovf} = try parseF64(str)
    if ovf do
        fail OverflowError{}
    if eat != str.count do
        fail SyntaxError{}
    return v
}

// Converts the whole of `str` to the integer or floating-point type `T`.
//
// The conversion and its failures are those of the matching `toX` function, such as
// [[Core.StrConv.toS32]] for `s32`.
func(T) toNum(str: string)->T fail
{
    #static switch T
    {
    case u8:  return try toU8(str)
    case u16: return try toU16(str)
    case u32: return try toU32(str)
    case u64: return try toU64(str)
    case s8:  return try toS8(str)
    case s16: return try toS16(str)
    case s32: return try toS32(str)
    case s64: return try toS64(str)
    case f32: return try toF32(str)
    case f64: return try toF64(str)
    default:  #error("invalid type")
    }

    return 0
}
