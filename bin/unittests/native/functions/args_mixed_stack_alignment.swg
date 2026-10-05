#global private

alias StackWords = #simd [4] u32

struct StackSummary
{
    checksum: u64
    first:    u64
    last:     u64
}

// Exhaust both register banks before a scalar, a wide vector and trailing scalars.
// The hidden return pointer changes which integer first reaches the stack.
#[Swag.NoInline]
func sumMixedStack(i0, i1, i2, i3, i4, i5: u64, f0, f1, f2, f3, f4, f5: f64, head: u64, wide: StackWords, tail: u64, last: f64)->u64
{
    let integers = i0 + 2 * i1 + 3 * i2 + 4 * i3 + 5 * i4 + 6 * i5
    let floats   = cast(u64) (f0 + 2 * f1 + 3 * f2 + 4 * f3 + 5 * f4 + 6 * f5)
    let words    = cast(u64) wide[0] + 2 * cast(u64) wide[1] + 3 * cast(u64) wide[2] + 4 * cast(u64) wide[3]
    return integers + floats + 7 * head + words + 11 * tail + 13 * cast(u64) last
}

#[Swag.NoInline]
func returnMixedStack(i0, i1, i2, i3, i4, i5: u64, f0, f1, f2, f3, f4, f5: f64, head: u64, wide: StackWords, tail: u64, last: f64)->StackSummary
{
    return {checksum: sumMixedStack(i0, i1, i2, i3, i4, i5, f0, f1, f2, f3, f4, f5, head, wide, tail, last), first: head, last: tail}
}

#[Swag.CallingConvention(.C)]
#[Swag.NoInline]
func sumPlatformStack(i0, i1, i2, i3, i4, i5: u64, f0, f1, f2, f3, f4, f5: f64, head: u64, wide: StackWords, tail: u64, last: f64)->u64
{
    return sumMixedStack(i0, i1, i2, i3, i4, i5, f0, f1, f2, f3, f4, f5, head, wide, tail, last)
}

#test
{
    let words = cast(StackWords) [31'u32, 32, 33, 34]
    let value = sumMixedStack(1, 2, 3, 4, 5, 6, 11, 12, 13, 14, 15, 16, 21, words, 22, 23)
    Swag.assert(value == 1410)
}

#test
{
    let words = cast(StackWords) [31'u32, 32, 33, 34]
    let value = returnMixedStack(1, 2, 3, 4, 5, 6, 11, 12, 13, 14, 15, 16, 21, words, 22, 23)
    Swag.assert(value.checksum == 1410)
    Swag.assert(value.first == 21)
    Swag.assert(value.last == 22)
}

#test
{
    let words = cast(StackWords) [31'u32, 32, 33, 34]
    let value = sumPlatformStack(1, 2, 3, 4, 5, 6, 11, 12, 13, 14, 15, 16, 21, words, 22, 23)
    Swag.assert(value == 1410)
}
