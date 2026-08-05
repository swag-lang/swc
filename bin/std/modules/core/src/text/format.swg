#global public
#global namespace Format

using Swag

// Check if this is a valid 'fmt/values' pair, coherent with 'format' specification
func checkFormat(fct: string, fmt: string, values: ...)
{
    let cptPercent = countPercent(fmt)
    if cptPercent != @countof(values)
    {
        let str = toString("bad number of arguments to [[%]] ([[%]] requested, [[%]] provided)", fct, cptPercent, @countof(values))
        @compilererror(str, #location(values))
    }
}

// Count the number of valid '%' placeholders in the string format.
// Note that '%%' will not be counted, as this represents the '%' character
#[ConstExpr]
func countPercent(fmt: string)->u32
{
    var cptPercent = 0'u32
    for var i = 0; i < @countof(fmt); i += 1
    {
        if fmt[i] != '%'u8 do
            continue

        if i == @countof(fmt) - 1 or fmt[i + 1] != '%'u8 do
            cptPercent += 1
        else do
            i += 1
    }

    return cptPercent
}

// Format a string in 'dest'.
// Can be a lot faster than the convenient version which returns a String.
func replaceString(dest: *String, fmt: string, values: ...)
{
    var buf: ConcatBuffer

    buf.allocator = dest.allocator
    buf.setFirstBucket(@mkslice(dest.buffer, dest.capacity))

    append(&buf, fmt, values)

    buf.makeLinear()
    let {data, count, capacity} = buf.eatBuffer()

    dest.buffer   = data
    dest.length   = count
    dest.capacity = capacity
}

// Format a string and returns the result as a String.
// Use '%' as a place holder for a value.
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
// - See [[ConvertFormatInt.setFormat]] for some valid format options
// - See [[ConvertFormatFloat.setFormat]] for some valid format options
func toString(fmt: string, values: ...)->String
{
    var buf: ConcatBuffer

    append(&buf, fmt, values)

    return buf.toString()
}

// Format a string and put the result in a ConcatBuffer.
func append(buf: *ConcatBuffer, fmt: string, values: ...)
{
    let ptr = @dataof(fmt)
    let cpt = @countof(fmt)

    var idx       = 0'u32
    var nextIdx   = 0'u32
    var paramIdx  = 0'u32
    let numParams = @countof(values)

    let convFmt: StrConv.ConvertFormat

    while nextIdx < cpt
    {
        if ptr[nextIdx] == '%'u8
        {
            // Add remaining text, and starts again after the mark
            buf.addBytes(cast(const [..] u8) @mkslice(ptr + idx, cast(u64) (nextIdx - idx)))
            idx     = nextIdx + 1
            nextIdx = idx

            // Deal with the parameter. %% is for one % only
            if ptr[nextIdx] == '%'u8
            {
                buf.addNative('%'u8)
                nextIdx += 1
                idx     += 1
                continue
            }

            // Optional string format, like '%{whatever}'
            var strFormat: #null const [..] u8
            if ptr[nextIdx] == '{'u8
            {
                nextIdx += 1
                let ptrFormat   = ptr + nextIdx
                var countFormat = 0'u32
                while ptr[nextIdx] and ptr[nextIdx] != '}'u8
                {
                    countFormat += 1
                    nextIdx     += 1
                }

                if ptr[nextIdx] do
                    nextIdx += 1
                idx       = nextIdx
                strFormat = @mkslice(ptrFormat, cast(u64) countFormat)
            }

            // '#' starts an explicit 0-based argument index, so a translation can reorder
            // its arguments. It targets one placeholder only and leaves the running
            // position of the plain '%' placeholders untouched.
            var useIdx = paramIdx
            if strFormat != null and @countof(strFormat) and strFormat[0] == '#'u8
            {
                let spec                  = cast(string) @mkslice(@dataof(strFormat) + 1, @countof(strFormat) - 1)
                let {argIdx, eatCount, ?} = expect StrConv.parseU64(spec)
                Debug.assert(eatCount != 0, "missing argument index after '#'")
                useIdx = cast(u32) argIdx

                // An optional conversion format follows ':'.
                strFormat = null
                if eatCount < @countof(spec) and spec[eatCount] == ':'u8 do
                    strFormat = @mkslice(@dataof(spec) + eatCount + 1, @countof(spec) - eatCount - 1)
            }
            else do
                paramIdx += 1

            // Deal with the parameter
            Debug.assert(useIdx < numParams, "not enough 'format' parameters")
            StrConv.convertAny(buf, values[useIdx], convFmt, cast(#null string) strFormat)
        }
        else
        {
            nextIdx += 1
        }
    }

    // Add remaining text
    if idx < nextIdx do
        buf.addBytes(cast(const [..] u8) @mkslice(ptr + idx, cast(u64) nextIdx - idx))
}

// String interpolation.
// Format is `{<value to interpolate>:format}`
// A mixin: the interpolated expressions are caller-side names, so the generated
// code must resolve in the caller scope; the internal locals use "#uniq?".
#[Mixin]
func toInterp(buf: *ConcatBuffer, exp: string)
{
    #ast
    {
        var sb: StrConv.StringBuilder
        sb.appendString("var #uniq1: StrConv.ConvertFormat\n")

        var idx = 0'u64
        while idx != @countof(exp)
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

// String interpolation.
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

    var value = cast(f64) bytes / 1024.0
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
