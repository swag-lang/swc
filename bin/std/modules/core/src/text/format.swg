#global public
#global namespace Format

using Swag

// Raises a compiler error when `fmt` does not have exactly one placeholder per value.
//
// `fct` names the formatting function in the message, which points at `values`.
func checkFormat(fct: string, fmt: string, values: ...)
{
    let placeholderCount = countPercent(fmt)
    if placeholderCount != values.count
    {
        let message = toString("bad number of arguments to [[%]] ([[%]] requested, [[%]] provided)",
                               fct,
                               placeholderCount,
                               values.count)
        Swag.compilerError(message, #location(values))
    }
}

// Returns the number of '%' placeholders in `fmt`.
//
// '%%' is an escaped '%' and does not count.
#[ConstExpr]
func countPercent(fmt: string)->u32
{
    var placeholderCount = 0'u32
    for var byteIndex = 0; byteIndex < fmt.count; byteIndex += 1
    {
        if fmt[byteIndex] != '%'u8 do
            continue

        if byteIndex == fmt.count - 1 or fmt[byteIndex + 1] != '%'u8 do
            placeholderCount += 1
        else do
            byteIndex += 1
    }

    return placeholderCount
}

// Replaces `dest` with `fmt` formatted with `values`, reusing its capacity when sufficient.
//
// Formatting completes before the destination changes, so `fmt` and `values` may borrow it.
// The destination keeps its allocator and contains a null-terminated string, including when empty.
func replaceString(dest: *String, fmt: string, values: ...)
{
    var buf: ConcatBuffer
    buf.allocator = dest.allocator
    append(&buf, fmt, values)

    dest.clear()
    dest.grow(buf.count() + 1)
    for bucket in buf do
        dest.append(Swag.makeString(bucket.data, bucket.count))
    dest.storage()[dest.length] = 0
}

// Returns a new [[Core.String]] holding `fmt` with each '%' placeholder replaced by the next value.
//
// Each '%' stands for the next value of `values`, and '%%' writes a single '%'.
// ```swag
// let x = Format.toString("my life is %", myLife)
// ```
// '%' can be followed by a format option between '{}'.
// ```swag
// let x = Format.toString("my life in hexadecimal is %{X}", myLife)
// ```
// '%{#n}' targets the 0-based argument 'n' instead of the next one, so a translated
// format string can reorder its arguments. An indexed placeholder does not advance the
// running argument position, and it can carry a format option after ':'.
// ```swag
// let x = Format.toString("%{#1} before %{#0:X}", 255, "written")
// ```
// - See [[Core.StrConv.ConvertFormatInt.setFormat]] for the integer format options.
// - See [[Core.StrConv.ConvertFormatFloat.setFormat]] for the floating-point format options.
func toString(fmt: string, values: ...)->String
{
    var buf: ConcatBuffer
    append(&buf, fmt, values)
    return buf.toString()
}

// Appends `fmt` formatted with `values` to `buf`, following the rules of [[Core.Format.toString]].
func append(buf: *ConcatBuffer, fmt: string, values: ...)
{
    let bytes     = fmt.buffer
    let byteCount = fmt.count

    var literalStart  = 0'u32
    var cursor        = 0'u32
    var nextArgument  = 0'u32
    let argumentCount = values.count

    let defaultFormat: StrConv.ConvertFormat

    while cursor < byteCount
    {
        if bytes[cursor] != '%'u8
        {
            cursor += 1
            continue
        }

        // Add the text before the mark, and start again after it.
        buf.addBytes(fmt[literalStart until cursor])
        literalStart = cursor + 1
        cursor       = literalStart

        // An escaped percent consumes no argument. This view has no guaranteed terminator;
        // check the end before reading beyond a percent or a format delimiter.
        if cursor < byteCount and bytes[cursor] == '%'u8
        {
            buf.addNative('%'u8)
            cursor       += 1
            literalStart += 1
            continue
        }

        // Optional string format, like '%{whatever}'
        var formatOptions: const [..] u8?
        if cursor < byteCount and bytes[cursor] == '{'u8
        {
            cursor += 1
            let optionStart  = bytes + cursor
            var optionLength = 0'u32
            while cursor < byteCount and bytes[cursor] != '}'u8
            {
                optionLength += 1
                cursor       += 1
            }

            if cursor < byteCount do
                cursor += 1
            literalStart  = cursor
            formatOptions = Swag.makeSlice(optionStart, cast(u64, optionLength))
        }

        // '#' starts an explicit 0-based argument index, so a translation can reorder
        // its arguments. It targets one placeholder only and leaves the running
        // position of the plain '%' placeholders untouched.
        var argumentIndex = nextArgument
        if formatOptions != null and formatOptions.count and formatOptions[0] == '#'u8
        {
            let indexSpec = cast(string, Swag.makeSlice(formatOptions.buffer + 1, formatOptions.count - 1))
            let {parsedIndex, consumedBytes, ?} = expect StrConv.parseU64(indexSpec)
            Swag.assert(consumedBytes != 0, "missing argument index after '#'")
            argumentIndex = cast(u32, parsedIndex)

            // An optional conversion format follows ':'.
            formatOptions = null
            if consumedBytes < indexSpec.count and indexSpec[consumedBytes] == ':'u8 do
                formatOptions = Swag.makeSlice(indexSpec.buffer + consumedBytes + 1,
                                               indexSpec.count - consumedBytes - 1)
        }
        else
        {
            nextArgument += 1
        }

        // Convert the selected argument with this placeholder's options.
        Swag.assert(argumentIndex < argumentCount, "not enough 'format' parameters")
        StrConv.convertAny(buf, values[argumentIndex], defaultFormat, cast(string?, formatOptions))
    }

    // Add the remaining text.
    if literalStart < cursor do
        buf.addBytes(fmt[literalStart until cursor])
}

// Appends `exp` to `buf`, with each `{expr}` or `{expr:format}` replaced by the value of `expr`.
//
// This is a mixin: the interpolated expressions are caller-side names, so the generated
// code must resolve in the caller scope; the internal locals use "#uniq?".
#[Mixin]
func toInterp(buf: *ConcatBuffer, exp: string)
{
    #ast
    {
        var sb: StrConv.StringBuilder
        sb.appendString("var #uniq1: StrConv.ConvertFormat\n")

        var idx = 0'u64
        while idx != exp.count
        {
            // To the interpolated string if it exists
            var idxE = Utf8.indexOf(exp, "{", startByteIndex: idx)
            if idxE == Swag.U64.Max
            {
                sb.appendFormat("buf.addBytes(\"%\")\n", exp[idx to])
                break
            }

            if idx != idxE do
                sb.appendFormat("buf.addBytes(\"%\")\n", exp[idx until idxE])

            // Find the end of the interpolated string, or the start of the format
            idx  = idxE + 1
            idxE = Utf8.indexOfAny(exp, "}:", startByteIndex: idx)
            if idxE == Swag.U64.Max
            {
                sb.appendFormat("buf.addBytes(\"%\")\n", exp[idx - 1 to])
                break
            }

            let value = exp[idx until idxE]
            idx = idxE + 1

            // Format
            var format: string
            if exp[idxE] == ':'u8
            {
                idxE = Utf8.indexOf(exp, "}", startByteIndex: idx)
                if idxE != Swag.U64.Max
                {
                    format = exp[idx until idxE]
                    idx    = idxE + 1
                }
            }

            sb.appendFormat("StrConv.convert(buf, %, #uniq1, \"%\")\n", value, format)
        }

        let generated = sb.moveToString()
        return generated.toString()
    }
}

// Returns a new [[Core.String]] holding `exp` interpolated like the overload that appends to a [[Core.ConcatBuffer]].
#[Mixin]
func toInterp(exp: string)->String
{
    var #uniq0: ConcatBuffer
    toInterp(&#uniq0, exp)
    return #uniq0.moveToString()
}

// Formats a byte count as a compact human-readable size, such as `"312 B"`, `"4.10 KB"` or `"13.4 MB"`.
//
// Units are 1024-based with the conventional `KB`/`MB`/`GB`/`TB` labels. Scaled values keep
// three significant digits; exact byte counts below 1 KB are printed unscaled.
func byteSize(bytes: u64)->String
{
    if bytes < 1024 do
        return toString("% B", bytes)

    var value = cast(f64, bytes) / 1024.0
    var unit  = "KB"
    if value >= 1024
    {
        value /= 1024.0
        unit  = "MB"
    }

    if value >= 1024
    {
        value /= 1024.0
        unit  = "GB"
    }

    if value >= 1024
    {
        value /= 1024.0
        unit  = "TB"
    }

    if value >= 100 do
        return toString("%{f0} %", value, unit)
    if value >= 10 do
        return toString("%{f1} %", value, unit)
    return toString("%{f2} %", value, unit)
}
