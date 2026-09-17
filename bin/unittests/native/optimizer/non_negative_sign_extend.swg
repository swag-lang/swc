#global private

// Small non-negative dword results returned as s32 skip their sign
// extension. Counts, masked and shifted values must keep their value, and a
// sum that can reach the sign bit must stay negative when it does.

#[Swag.Optimize(true), Swag.NoInline]
func countTrue(a, b, c: bool)->s32 => cast(s32) a + cast(s32) b + cast(s32) c

#[Swag.Optimize(true), Swag.NoInline]
func byteSum(a, b: u8)->s32 => cast(s32) a + cast(s32) b

#[Swag.Optimize(true), Swag.NoInline]
func topBits(x: u32)->s32 => cast(s32) (x >> 20)

#[Swag.Optimize(true), Swag.NoInline]
func lowPart(x: s32)->s64 => cast(s64) (x & 0x7FFF)

#[Swag.Optimize(true), Swag.NoInline, Swag.Safety(.Overflow, false)]
func wideSum(a, b: s32)->s64 => cast(s64) (a + b)

#[Swag.Optimize(true), Swag.NoInline]
func pick(flag: bool, a, b: u8)->s32 => flag ? cast(s32) a : cast(s32) b * 3

#test
{
    Swag.assert(countTrue(true, true, true) == 3 and countTrue(false, true, false) == 1)
    Swag.assert(byteSum(255, 255) == 510 and byteSum(0, 1) == 1)
    Swag.assert(topBits(0xFFFFFFFF) == 4095 and topBits(0x00100000) == 1)
    Swag.assert(lowPart(-1) == 0x7FFF and lowPart(0x12345) == 0x2345)
    Swag.assert(wideSum(0x7FFFFFFF, 1) == -0x80000000's64)
    Swag.assert(wideSum(-5, 2) == -3)
    Swag.assert(pick(true, 200, 100) == 200 and pick(false, 200, 255) == 765)
}
