#global private

// A memory intrinsic whose size is a compile-time constant is materialized by the compiler
// instead of calling the runtime, so the two forms are two implementations of one contract and
// must answer identically. Regression: 'Swag.memcmp' loaded its bytes sign-extended on the
// materialized path and zero-extended in the runtime, so a differing byte of 0x80 or above made
// the two disagree about which sequence was greater.

#[Swag.NoInline]
func compareDynamic(left, right: #null const [*] void, size: u64)->s32
{
    return Swag.memcmp(left, right, size)
}

#[Swag.NoInline]
func fillDynamic(target: #null [*] void, value: u8, size: u64)
{
    Swag.memset(target, value, size)
}

// The sizes below straddle every block width the materialized forms use: the vector block, the
// machine word, and each smaller tail step.
#[Swag.NoInline]
func compareStatic1(left, right: const [*] u8)->s32 => Swag.memcmp(left, right, 1)
#[Swag.NoInline]
func compareStatic7(left, right: const [*] u8)->s32 => Swag.memcmp(left, right, 7)
#[Swag.NoInline]
func compareStatic16(left, right: const [*] u8)->s32 => Swag.memcmp(left, right, 16)
#[Swag.NoInline]
func compareStatic17(left, right: const [*] u8)->s32 => Swag.memcmp(left, right, 17)
#[Swag.NoInline]
func compareStatic64(left, right: const [*] u8)->s32 => Swag.memcmp(left, right, 64)

#[Swag.NoInline]
func fillStatic8(target: [*] u8, value: u8) { Swag.memset(target, value, 8) }
#[Swag.NoInline]
func fillStatic64(target: [*] u8, value: u8) { Swag.memset(target, value, 64) }
#[Swag.NoInline]
func fillStatic67(target: [*] u8, value: u8) { Swag.memset(target, value, 67) }

// A byte at or above 0x80 orders above a smaller one: 'Swag.memcmp' reads bytes, not signed chars.
#test
{
    var high: [64] u8
    var low:  [64] u8

    for index in 64
    {
        high[index] = 0x20
        low[index]  = 0x20
    }

    high[3] = 0xFF
    low[3]  = 0x01
    Swag.assert(compareStatic64(&high[0], &low[0]) > 0)
    Swag.assert(compareStatic64(&low[0], &high[0]) < 0)
    Swag.assert(compareStatic64(&high[0], &low[0]) == compareDynamic(&high[0], &low[0], 64))
    Swag.assert(compareStatic64(&low[0], &high[0]) == compareDynamic(&low[0], &high[0], 64))
}

// The materialized answer matches the runtime one for a difference at every position, whatever
// block width covers it.
#test
{
    var left:  [64] u8
    var right: [64] u8
    for index in 64
    {
        left[index]  = cast(u8) ((index * 7 + 3) & 0xFF)
        right[index] = left[index]
    }

    for position in 64
    {
        let saved = right[position]
        right[position] = saved ^ 0x80'u8

        Swag.assert(compareStatic64(&left[0], &right[0]) == compareDynamic(&left[0], &right[0], 64))
        if position < 17 do
            Swag.assert(compareStatic17(&left[0], &right[0]) == compareDynamic(&left[0], &right[0], 17))
        if position < 16 do
            Swag.assert(compareStatic16(&left[0], &right[0]) == compareDynamic(&left[0], &right[0], 16))
        if position < 7 do
            Swag.assert(compareStatic7(&left[0], &right[0]) == compareDynamic(&left[0], &right[0], 7))
        if position < 1 do
            Swag.assert(compareStatic1(&left[0], &right[0]) == compareDynamic(&left[0], &right[0], 1))

        right[position] = saved
    }

    Swag.assert(compareStatic64(&left[0], &right[0]) == 0)
    Swag.assert(compareStatic17(&left[0], &right[0]) == 0)
    Swag.assert(compareStatic16(&left[0], &right[0]) == 0)
    Swag.assert(compareStatic7(&left[0], &right[0]) == 0)
    Swag.assert(compareStatic1(&left[0], &right[0]) == 0)
}

// A non-zero fill writes the same bytes whether the compiler materializes it or the runtime does,
// at sizes below and above the width where the fill widens to a vector register.
#test
{
    var materialized: [80] u8
    var called:       [80] u8

    fillStatic8(&materialized[0], 0xA5)
    fillDynamic(&called[0], 0xA5, 8)
    Swag.assert(materialized == called)

    fillStatic64(&materialized[0], 0x5A)
    fillDynamic(&called[0], 0x5A, 64)
    Swag.assert(materialized == called)

    fillStatic67(&materialized[0], 0xC3)
    fillDynamic(&called[0], 0xC3, 67)
    Swag.assert(materialized == called)
}
