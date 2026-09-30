#global private

// A guard the optimizer proves can never fire is removed, and so is one that repeats a test
// an earlier guard already made. These cases stand on both sides of each proof: the guard
// that is gone must leave the right value, and the one that only looks alike must still fire.

const M32 = 0xFFFFFFFF'u64

#[Swag.NoInline]
func opaqueU32(v: u32)->u32 => v

#[Swag.NoInline]
func opaqueU64(v: u64)->u64 => v

// The sum of two 32-bit values held in 64 bits never carries, and its low half always fits.
#[Swag.Safety(.Overflow, true)]
func addWrapping(left, right: u32)->u32 => cast(u32) ((cast(u64) left + right) & M32)

#test
{
    Swag.assert(addWrapping(opaqueU32(0xFFFFFFFF), opaqueU32(0xFFFFFFFF)) == 0xFFFFFFFE)
    Swag.assert(addWrapping(opaqueU32(0xFFFFFFFF), opaqueU32(1)) == 0)
    Swag.assert(addWrapping(opaqueU32(7), opaqueU32(9)) == 16)
}

// Without the mask the same sum reaches 33 bits: the conversion still has to be checked.
#test
{
    #[Swag.Safety(.Overflow, true)]
    func addNarrowing(left, right: u32)->u32
    {
        return cast(u32) (cast(u64) left + right)     // swc-expected-error {{safety_err_runtime}}
    }

    Swag.assert(addNarrowing(opaqueU32(7), opaqueU32(9)) == 16)
    discard addNarrowing(opaqueU32(0xFFFFFFFF), opaqueU32(1))
}

// One operand with no bound keeps the carry possible. The operand is read from a global
// so that the call cannot be folded into a compile-time error.
var g_Wide = Swag.U64.Max

#test
{
    #[Swag.Safety(.Overflow, true)]
    func addWide(left: u32, right: u64)->u64
    {
        return cast(u64) left + right     // swc-expected-error {{safety_err_runtime}}
    }

    Swag.assert(addWide(opaqueU32(1), opaqueU64(2)) == 3)
    discard addWide(opaqueU32(1), g_Wide)
}

// A running total is bounded by nothing, whatever the width of what it accumulates.
#test
{
    #[Swag.Safety(.Overflow, true)]
    func accumulate(start: u64, bytes: [4] u8)->u64
    {
        var total = start
        for value in bytes do
            total += value     // swc-expected-error {{safety_err_runtime}}
        return total
    }

    Swag.assert(accumulate(opaqueU64(10), [1, 2, 3, 4]) == 20)
    discard accumulate(opaqueU64(Swag.U64.Max - 5), [1, 2, 3, 4])
}

// The same index tested three times in a row is tested once, and still guarded.
#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func mix(values: *[4] u32, a, b: u64)
    {
        values[][a] = values[][a] + values[][b]
        values[][b] ^= values[][a]
    }

    var values: [4] u32 = [1, 2, 3, 4]
    mix(&values, opaqueU64(0), opaqueU64(3))
    Swag.assert(values[0] == 5 and values[3] == 1)
}

// An index that changed between two accesses is a new test, not a repeated one.
#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func readTwice(values: *[4] u32, first, second: u64)->u32
    {
        var index = first
        let head  = values[][index]
        index = second
        return head + values[][index]     // swc-expected-error {{safety_err_runtime}}
    }

    var values: [4] u32 = [1, 2, 3, 4]
    Swag.assert(readTwice(&values, opaqueU64(0), opaqueU64(3)) == 5)
    discard readTwice(&values, opaqueU64(0), opaqueU64(4))
}

// A test the program wrote itself is not a guard: the access after it keeps its own.
#test
{
    #[Swag.Safety(.BoundCheck, true)]
    func readAfterTest(values: *[4] u32, index: u64)->u32
    {
        var extra = 0'u32
        if index < 4 do
            extra = 1
        return extra + values[][index]     // swc-expected-error {{safety_err_runtime}}
    }

    var values: [4] u32 = [1, 2, 3, 4]
    Swag.assert(readAfterTest(&values, opaqueU64(2)) == 4)
    discard readAfterTest(&values, opaqueU64(4))
}
