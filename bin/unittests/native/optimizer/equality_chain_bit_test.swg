#global private
using Swag

// A chain of equality tests of one value against nearby constants is one bit
// test. Every input byte must give the source answer: the `or` chain, its
// `and` of inequalities dual, constants away from zero, a span too wide for a
// word, and signed values that wrap.

#[Swag.Optimize(true), Swag.NoInline]
func isSpace(c: u8)->bool => c == ' ' or c == '\t' or c == '\n' or c == '\r'

#[Swag.Optimize(true), Swag.NoInline]
func isVowel(c: u8)->bool => c == 'a' or c == 'e' or c == 'i' or c == 'o' or c == 'u'

#[Swag.Optimize(true), Swag.NoInline]
func notDelimiter(c: u8)->bool => c != ',' and c != ';' and c != ':'

#[Swag.Optimize(true), Swag.NoInline]
func wideSpan(c: u32)->bool => c == 1 or c == 40 or c == 200

#[Swag.Optimize(true), Swag.NoInline]
func smallSigned(v: s32)->bool => v == -1 or v == 0 or v == 3

#[Swag.Optimize(true), Swag.NoInline]
func tags(v: u32)->bool => v == 100 or v == 101 or v == 140 or v == 163

#test
{
    for i in 256
    {
        let c = cast(u8) i
        Swag.assert(isSpace(c) == (c == 32 or c == 9 or c == 10 or c == 13))
        Swag.assert(isVowel(c) == (c == 97 or c == 101 or c == 105 or c == 111 or c == 117))
        Swag.assert(notDelimiter(c) == not (c == 44 or c == 59 or c == 58))
        Swag.assert(wideSpan(cast(u32) i) == (i == 1 or i == 40 or i == 200))
        Swag.assert(tags(cast(u32) i) == (i == 100 or i == 101 or i == 140 or i == 163))
    }
    Swag.assert(smallSigned(-1) and smallSigned(0) and smallSigned(3))
    Swag.assert(not smallSigned(1) and not smallSigned(-2) and not smallSigned(0x7FFFFFFF))
}
