#global namespace Globalization

using Swag

// Provides culture-specific signs, separators, grouping, and numeric formatting.
public struct NumberFormatInfo
{
    public
    {
        negativeSign:     u8     = '-'        // Sign written before negative values.
        positiveSign:     u8     = '+'        // Sign written before positive values when requested.
        decimalSeparator: u8     = '.'        // Separator between the integer and fractional parts.
        groupSeparator:   rune   = ','        // Unicode separator between groups in the integer part.
        groupSizes:       [2] u8 = [3, 0]     // Group widths from right to left; the last non-zero width repeats.
        groupSizeCount:   u8     = 1          // Number of entries from [[groupSizes]] that participate in grouping.
    }
}

public impl NumberFormatInfo
{
    internal mtd const groupSize(index: u64)->u64
    {
        if !.groupSizeCount do
            return 0
        let safeCount = Math.min(cast(u64) .groupSizeCount, @countof(.groupSizes))
        let safeIndex = Math.min(index, safeCount - 1)
        return .groupSizes[safeIndex]
    }

    internal mtd const isGroupBoundary(remainingDigits: u64)->bool
    {
        if !.groupSizeCount or !.groupSeparator do
            return false

        var boundary = .groupSize(0)
        var index    = 1'u64
        while boundary and boundary <= 64
        {
            if remainingDigits == boundary do
                return true
            let next = .groupSize(index)
            if !next do
                return false
            boundary += next
            index    += 1
        }

        return false
    }

    internal mtd const appendUnsigned(result: *String, value: u64, grouped: bool)
    {
        var digits: [20] u8 = undefined
        var count           = 0'u64
        var current         = value
        while true
        {
            digits[count] = cast(u8) ('0'u8 + current % 10)
            count         += 1
            current       /= 10
            if !current do
                break
        }

        for i in count
        {
            let remaining = count - i
            if grouped and i and .isGroupBoundary(remaining) do
                result.append(.groupSeparator)
            result.append(digits[remaining - 1])
        }
    }

    // Formats an unsigned decimal integer, optionally applying this culture's grouping rules.
    mtd const format(value: u64, grouped = false)->String
    {
        var result: retval
        .appendUnsigned(&result, value, grouped)
        return result
    }

    // Formats a signed decimal integer, optionally applying this culture's grouping rules.
    mtd const format(value: s64, grouped = false)->String
    {
        var result: retval
        if value < 0
        {
            result.append(.negativeSign)
            let magnitude = cast(u64) (-(value + 1)) + 1
            .appendUnsigned(&result, magnitude, grouped)
        }
        else do
            .appendUnsigned(&result, cast(u64) value, grouped)
        return result
    }

    // Formats a finite decimal value with a fixed number of fractional digits.
    //
    // `decimals` must be at most 18. Values are rounded to the nearest representable
    // unit at that precision before grouping is applied to the integer part.
    mtd const format(value: f64, decimals = 2'u8, grouped = false)->String
    {
        Debug.assert(decimals <= 18, "numeric precision is too large")
        Debug.assert(Math.isFinite(value), "cannot format a non-finite number")

        var scale = 1'u64
        for decimals do
            scale *= 10

        let negative = value < 0
        let absolute = Math.abs(value)
        Debug.assert(absolute <= cast(f64) Swag.U64.Max / cast(f64) scale, "numeric value is too large at the requested precision")
        let scaled   = cast(u64) Math.round(absolute * cast(f64) scale)
        let whole    = decimals ? scaled / scale : scaled
        let fraction = decimals ? scaled % scale : 0

        var result: retval
        if negative do
            result.append(.negativeSign)
        .appendUnsigned(&result, whole, grouped)
        if decimals
        {
            result.append(.decimalSeparator)
            var divisor = scale / 10
            for decimals
            {
                result.append(cast(u8) ('0'u8 + (fraction / divisor) % 10))
                divisor /= 10
            }
        }

        return result
    }
}
