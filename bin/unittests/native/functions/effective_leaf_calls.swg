#global private

#[Swag.Inline]
func inlineMix(value: u64)->u64 => ((value << 7) | (value >> 57)) ^ 0x9E3779B97F4A7C15

#[Swag.NoInline, Swag.Optimize(true)]
func effectiveLeaf(value: u64)->u64 => inlineMix(value) ^ 0x1122334455667788

#[Swag.NoInline, Swag.Optimize(true), Swag.Safety(.Overflow, false)]
func nonLeaf(value: u64)->u64 => effectiveLeaf(value) + 3

#[Swag.NoInline, Swag.Optimize(true), Swag.Safety(.Overflow, false)]
func evenStep(remaining: s32, value: u64)->u64
{
    if remaining == 0 do
        return value
    return oddStep(remaining - 1, value + 1)
}

#[Swag.NoInline, Swag.Optimize(true), Swag.Safety(.Overflow, false)]
func oddStep(remaining: s32, value: u64)->u64
{
    if remaining == 0 do
        return value
    return evenStep(remaining - 1, value + 1)
}

// Explicit inline recursion falls back to a runtime call. Its retained
// template edges must not form a lowering wait cycle.
#[Swag.Inline, Swag.Safety(.Overflow, false)]
func inlineEven(remaining: s32, value: u64)->u64
{
    if remaining == 0 do
        return value
    return inlineOdd(remaining - 1, value + 1)
}

#[Swag.Inline, Swag.Safety(.Overflow, false)]
func inlineOdd(remaining: s32, value: u64)->u64
{
    if remaining == 0 do
        return value
    return inlineEven(remaining - 1, value + 1)
}

#[Swag.NoInline, Swag.Optimize(true), Swag.Safety(.Overflow, false)]
func expandedRecursion(remaining: s32, value: u64)->u64 => inlineEven(remaining, value)

#[Swag.NoInline, Swag.Optimize(false), Swag.Safety(.Overflow, false)]
func reference(seed: u64, count: s32)->u64
{
    var a        = seed
    var b        = seed ^ 0xA5A5A5A5A5A5A5A5
    var c        = seed + 17
    var d        = seed - 9
    var floating = 0.0'f64
    for index in count
    {
        let mixed = effectiveLeaf(a)
        a        = mixed + b
        b        ^= c + cast(u64, index)
        c        = nonLeaf(d) ^ mixed
        d        = evenStep(index % 5, a ^ c)
        d        ^= expandedRecursion(index % 5, d)
        floating += cast(f64, index) + 0.5'f64
    }
    return a ^ b ^ c ^ d ^ cast(u64, floating * 2.0'f64)
}

#[Swag.NoInline, Swag.Optimize(true), Swag.Safety(.Overflow, false)]
func optimized(seed: u64, count: s32)->u64
{
    var a        = seed
    var b        = seed ^ 0xA5A5A5A5A5A5A5A5
    var c        = seed + 17
    var d        = seed - 9
    var floating = 0.0'f64
    for index in count
    {
        let mixed = effectiveLeaf(a)
        a        = mixed + b
        b        ^= c + cast(u64, index)
        c        = nonLeaf(d) ^ mixed
        d        = evenStep(index % 5, a ^ c)
        d        ^= expandedRecursion(index % 5, d)
        floating += cast(f64, index) + 0.5'f64
    }
    return a ^ b ^ c ^ d ^ cast(u64, floating * 2.0'f64)
}

#test
{
    for seed in [0'u64, 1, 0x0123456789ABCDEF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    {
        for count in [0's32, 1, 2, 3, 7, 16] do
            Swag.require(optimized(seed, count) == reference(seed, count))
    }
}
