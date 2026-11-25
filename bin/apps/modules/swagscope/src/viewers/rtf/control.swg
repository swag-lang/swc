#global internal
#global namespace Viewers.Rtf

using Core

// One control word or escaped symbol, borrowing its spelling from the document bytes.
struct Control
{
    word:      string = ""
    symbol:    u8
    number:    s32
    hasNumber: bool
    end:       u64
}

impl Control
{
    func parse(source: const [..] u8, start: u64)->Control fail
    {
        var result: #returntype
        var at = start + 1
        if at >= source.count do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        if not Latin1.isLetter(source[at])
        {
            result.symbol = source[at]
            result.end    = at + 1
            return result
        }

        let first = at
        while at < source.count and Latin1.isLetter(source[at]) do
            at += 1
        result.word = cast(string, source[first until at])
        var negative = false
        if at < source.count and source[at] == '-'
        {
            negative = true
            at       += 1
        }

        let limit = negative ? 2_147_483_648'u32 : 2_147_483_647'u32
        var magnitude: u32
        while at < source.count and Latin1.isDigit(source[at])
        {
            result.hasNumber = true
            let digit = cast(u32, source[at] - '0')
            if magnitude > (limit - digit) / 10 do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            magnitude = magnitude * 10 + digit
            at += 1
        }

        let signed = cast(s64, magnitude)
        result.number = cast(s32, negative ? -signed : signed)
        if at < source.count and source[at] == ' ' do
            at += 1
        result.end = at
        return result
    }
}
