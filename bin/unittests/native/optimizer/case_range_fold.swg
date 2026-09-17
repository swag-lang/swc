#global private

// Two ranges of one span that differ in a single bit become one range once
// that bit is masked. Ranges that cross the bit, or differ in two bits, must
// keep their own tests; every value of a byte and a few wide ones check it.

#[Swag.Optimize(true), Swag.NoInline]
func isLetter(c: u32)->bool => (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')

#[Swag.Optimize(true), Swag.NoInline]
func isHexLetter(c: u32)->bool => (c >= 'A' and c <= 'F') or (c >= 'a' and c <= 'f')

#[Swag.Optimize(true), Swag.NoInline]
func highPair(c: u32)->bool => (c >= 0x21 and c <= 0x3A) or (c >= 0x61 and c <= 0x7A)

#[Swag.Optimize(true), Swag.NoInline]
func lowPair(c: u32)->bool => (c >= 0x10 and c <= 0x17) or (c >= 0x18 and c <= 0x1F)

#[Swag.Optimize(true), Swag.NoInline]
func crossingPair(c: u32)->bool => (c >= 0x1C and c <= 0x23) or (c >= 0x3C and c <= 0x43)

#[Swag.Optimize(true), Swag.NoInline]
func twoBitPair(c: u32)->bool => (c >= 0x01 and c <= 0x1A) or (c >= 0x61 and c <= 0x7A)

func within(c, lo, hi: u32)->bool => c >= lo and c <= hi

#test
{
    for v in 0 until 512
    {
        let c = cast(u32) v
        Swag.assert(isLetter(c) == (within(c, 0x61, 0x7A) or within(c, 0x41, 0x5A)))
        Swag.assert(isHexLetter(c) == (within(c, 0x41, 0x46) or within(c, 0x61, 0x66)))
        Swag.assert(highPair(c) == (within(c, 0x21, 0x3A) or within(c, 0x61, 0x7A)))
        Swag.assert(lowPair(c) == within(c, 0x10, 0x1F))
        Swag.assert(crossingPair(c) == (within(c, 0x1C, 0x23) or within(c, 0x3C, 0x43)))
        Swag.assert(twoBitPair(c) == (within(c, 0x01, 0x1A) or within(c, 0x61, 0x7A)))
    }

    for c in [0x10000061'u32, 0xFFFFFF41, 0x80000041, 0x100041, 0xFFFFFFFF]
    {
        Swag.assert(not isLetter(c))
        Swag.assert(not highPair(c))
    }
}
