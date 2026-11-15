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

        while at < source.count and Latin1.isDigit(source[at])
        {
            result.hasNumber = true
            if result.number > 100_000_000 do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            result.number = result.number * 10 + cast(s32, source[at] - '0')
            at += 1
        }

        if negative do
            result.number = -result.number
        if at < source.count and source[at] == ' ' do
            at += 1
        result.end = at
        return result
    }
}
