#global public
#global namespace Format

using Swag

// Raises a compiler error when `fmt` does not have exactly one placeholder per value.
//
// `fct` names the formatting function in the message, which points at `values`.
func checkFormat(fct: string, fmt: string, values: ...)
{
    let cptPercent = countPercent(fmt)
    if cptPercent != values.count
    {
        let str = toString("bad number of arguments to [[%]] ([[%]] requested, [[%]] provided)", fct, cptPercent, values.count)
        Swag.compilerError(str, #location(values))
    }
}

// Returns the number of '%' placeholders in `fmt`.
//
// '%%' is an escaped '%' and does not count.
#[ConstExpr]
func countPercent(fmt: string)->u32
{
    var cptPercent = 0'u32
    for var i = 0; i < fmt.count; i += 1
    {
        if fmt[i] != '%'u8 do
            continue

        if i == fmt.count - 1 or fmt[i + 1] != '%'u8 do
            cptPercent += 1
        else do
            i += 1
    }

    return cptPercent
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
    let ptr = fmt.buffer
    let cpt = fmt.count

    var idx       = 0'u32
    var nextIdx   = 0'u32
    var paramIdx  = 0'u32
    let numParams = values.count

    let convFmt: StrConv.ConvertFormat

    while nextIdx < cpt
    {
        if ptr[nextIdx] == '%'u8
        {
            // Add the text before the mark, and start again after it.
            buf.addBytes(fmt[idx until nextIdx])
            idx     = nextIdx + 1
            nextIdx = idx

            // Deal with the parameter. %% is for one % only. The format is a view with no
            // guaranteed terminator: every read past a mark checks the end first.
            if nextIdx < cpt and ptr[nextIdx] == '%'u8
            {
                buf.addNative('%'u8)
                nextIdx += 1
                idx     += 1
                continue
            }

            // Optional string format, like '%{whatever}'
            var strFormat: const [..] u8?
            if nextIdx < cpt and ptr[nextIdx] == '{'u8
            {
                nextIdx += 1
                let ptrFormat   = ptr + nextIdx
                var countFormat = 0'u32
                while nextIdx < cpt and ptr[nextIdx] != '}'u8
                {
                    countFormat += 1
                    nextIdx     += 1
                }

                if nextIdx < cpt do
                    nextIdx += 1
                idx       = nextIdx
                strFormat = Swag.makeSlice(ptrFormat, cast(u64) countFormat)
            }

            // '#' starts an explicit 0-based argument index, so a translation can reorder
            // its arguments. It targets one placeholder only and leaves the running
            // position of the plain '%' placeholders untouched.
            var useIdx = paramIdx
            if strFormat != null and strFormat.count and strFormat[0] == '#'u8
            {
                let spec = cast(string) Swag.makeSlice(strFormat.buffer + 1, strFormat.count - 1)
                let {argIdx, eatCount, ?} = expect StrConv.parseU64(spec)
                Swag.assert(eatCount != 0, "missing argument index after '#'")
                useIdx = cast(u32) argIdx

                // An optional conversion format follows ':'.
                strFormat = null
                if eatCount < spec.count and spec[eatCount] == ':'u8 do
                    strFormat = Swag.makeSlice(spec.buffer + eatCount + 1, spec.count - eatCount - 1)
            }
            else do
                paramIdx += 1

            // Deal with the parameter
            Swag.assert(useIdx < numParams, "not enough 'format' parameters")
            StrConv.convertAny(buf, values[useIdx], convFmt, cast(string?) strFormat)
        }
        else
        {
            nextIdx += 1
        }
    }

    // Add the remaining text.
    if idx < nextIdx do
        buf.addBytes(fmt[idx until nextIdx])
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
