#global private
#global #[Swag.Safety(.Overflow, false)]
using Swag

// A 32-bit move clears the upper half of its destination and a narrower one
// keeps the destination's own upper bits: neither makes the two registers
// equal. A truncated value read back at full width must not see the upper
// half of what it was truncated from, whichever pass renames the copy.

#[Swag.Optimize(true), Swag.NoInline]
func truncThenWiden(big: u64)->u64
{
    let low = cast(u32) big
    return cast(u64) low * 3
}

#[Swag.Optimize(true), Swag.NoInline]
func truncatedSum(a, b: u64)->u32 => cast(u32) (a + b)

#[Swag.Optimize(true), Swag.NoInline]
func widenedSum(a, b: u64)->u64 => cast(u64) truncatedSum(a, b) + 1

#[Swag.Optimize(true), Swag.NoInline]
func lowByteIndex(big: u64, table: const [*] u64)->u64
{
    let index = cast(u8) big
    return table[index] + cast(u64) index
}

struct PairU32
{
    x, y: u32
}

// The overflow checks call out, so the register holding the truncated field
// is saved around the calls and the allocator runs again on physical code.
#[Swag.Optimize(true), Swag.Safety(.Overflow, true), Swag.NoInline]
func checkedPair(a: u64, p: PairU32, b: u64)->u64 => a * 1000000 + cast(u64) p.x * 1000 + cast(u64) p.y + b

#test
{
    Swag.assert(truncThenWiden(0x100000005) == 15)
    Swag.assert(truncThenWiden(0xFFFFFFFF00000001) == 3)
    Swag.assert(widenedSum(0xFFFFFFFF, 2) == 2)
    Swag.assert(widenedSum(0x8000000000000000, 7) == 8)
    Swag.assert(checkedPair(7, PairU32{18, 24}, 3) == 7018027)

    var table: [4] u64
    table[2] = 40
    Swag.assert(lowByteIndex(0x7700000000000002, &table[0]) == 42)
}
