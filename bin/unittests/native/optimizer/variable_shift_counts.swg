#global private

// A shift reads the low byte of its count, so widening the count first is
// dropped. Counts that come from bytes, words and dwords, in both directions
// and with rotations, must still shift by the right amount.

#[Swag.Optimize(true), Swag.NoInline]
func lowMask(n: u32)->u64 => (1'u64 << n) - 1

#[Swag.Optimize(true), Swag.NoInline]
func shiftDown(x: u64, n: u8)->u64 => x >> n

#[Swag.Optimize(true), Swag.NoInline]
func shiftSigned(x: s64, n: u16)->s64 => x >> n

#[Swag.Optimize(true), Swag.NoInline]
func shiftDword(x: u32, n: u64)->u32 => x << n

#[Swag.Optimize(true), Swag.NoInline]
func shiftSum(x: u64, a, b: u8)->u64 => x << (a + b)

func slowShiftLeft(x: u64, n: u32)->u64
{
    var result = x
    for i in 0 until n do
        result = result * #wrap 2
    return result
}

#test
{
    let pattern = 0xF00D_CAFE_1234_5679'u64
    for v in 0 until 64
    {
        let n = cast(u32) v
        Swag.assert(lowMask(n) == slowShiftLeft(1, n) - 1)
        Swag.assert(shiftDown(pattern, cast(u8) v) == pattern / slowShiftLeft(1, n))
        Swag.assert(shiftSigned(-1, cast(u16) v) == -1)
        Swag.assert(shiftSum(pattern, cast(u8) (v / 2), cast(u8) (v - v / 2)) == slowShiftLeft(pattern, n))
        if v < 32 do
            Swag.assert(shiftDword(0x8765_4321, cast(u64) v) == cast #wrap (u32) slowShiftLeft(0x8765_4321, n))
    }
    Swag.assert(shiftSigned(-64, 3) == -8)
}
