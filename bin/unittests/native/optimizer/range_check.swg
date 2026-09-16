#global private
using Swag

// Two exits to the same label on the low and high bounds of one value are a
// single unsigned compare of the value minus the low bound. The boundaries,
// the values just outside them, the signed and unsigned forms, both orders
// and the narrow widths must all keep the source result.

#[Swag.Optimize(true), Swag.NoInline]
func isDigit(c: u8)->bool => c >= '0' and c <= '9'

#[Swag.Optimize(true), Swag.NoInline]
func toLower(c: u8)->u8 => (c >= 'A' and c <= 'Z') ? c + 32 : c

#[Swag.Optimize(true), Swag.NoInline]
func inSignedRange(x: s32)->bool => x >= -5 and x <= 20

#[Swag.Optimize(true), Swag.NoInline]
func highFirst(x: u64)->bool => x <= 1000 and x >= 900

#[Swag.Optimize(true), Swag.NoInline]
func countLetters(text: const [*] u8, count: u64)->u64
{
    var letters = 0'u64
    for i in count
    {
        let c = text[i]
        if c >= 'a' and c <= 'z' do
            letters += 1
    }

    return letters
}

#test
{
    for c in 256
    {
        let b = cast(u8) c
        Swag.assert(isDigit(b) == (c >= 48 and c <= 57))
        let lowered = (c >= 65 and c <= 90) ? b + 32 : b
        Swag.assert(toLower(b) == lowered)
    }

    for x in -40 to 40
    {
        let v = cast(s32) x
        Swag.assert(inSignedRange(v) == (x >= -5 and x <= 20))
    }
    Swag.assert(not inSignedRange(-0x7FFFFFFF - 1))
    Swag.assert(not inSignedRange(0x7FFFFFFF))

    Swag.assert(not highFirst(899))
    Swag.assert(highFirst(900))
    Swag.assert(highFirst(1000))
    Swag.assert(not highFirst(1001))
    Swag.assert(not highFirst(0xFFFFFFFFFFFFFFFF))

    let text = "Hello, World! zz`{"
    Swag.assert(countLetters(text.buffer, text.count) == 10)
}
