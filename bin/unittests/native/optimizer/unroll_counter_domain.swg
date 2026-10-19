#global private

// The trip count, rather than the absolute bound, controls full unrolling.
// Distinct signed/unsigned widths also exercise constant materialization at
// the edges of the counter domain and across signed zero.
#[Swag.NoInline, Swag.Optimize(true)]
func highOffset(dst: [*] u64)
{
    for i in 1000000000'u64 until 1000000004'u64 do
        dst[i - 1000000000] = i
}

#[Swag.NoInline, Swag.Optimize(true)]
func unsigned32(dst: [*] u32)
{
    for i in 0xFFFFFFFB'u32 until 0xFFFFFFFF'u32 do
        dst[i - 0xFFFFFFFB] = i
}

#[Swag.NoInline, Swag.Optimize(true)]
func unsigned64(dst: [*] u64)
{
    for var i = 0xFFFFFFFFFFFFFFF9'u64; i < 0xFFFFFFFFFFFFFFFF; i += 2 do
        dst[(i - 0xFFFFFFFFFFFFFFF9) / 2] = i
}

#[Swag.NoInline, Swag.Optimize(true)]
func signed32(dst: [*] s32)
{
    for var i = -4's32; i < 4; i += 2 do
        dst[(i + 4) / 2] = i
}

#[Swag.NoInline, Swag.Optimize(true)]
func signed64(dst: [*] s64)
{
    for var i = 0x7FFFFFFFFFFFFFF9's64; i < 0x7FFFFFFFFFFFFFFF; i += 2 do
        dst[(i - 0x7FFFFFFFFFFFFFF9) / 2] = i
}

// The closed-form sum has a separate arithmetic proof. It must not reuse
// its old, small-term formula for these large values before division by two.
#[Swag.NoInline, Swag.Optimize(true), Swag.Safety(.Overflow, false)]
func highSum()->u64
{
    var sum = 0'u64
    for i in 0xFFFFFFFFFFFFFFFB'u64 until 0xFFFFFFFFFFFFFFFF'u64 do
        sum += i
    return sum
}

#test
{
    var values: [4] u64
    highOffset(&values[0])
    for i in 4 do
        Swag.assert(values[i] == 1000000000 + i)

    var words: [4] u32
    unsigned32(&words[0])
    for i in 4 do
        Swag.assert(words[i] == 0xFFFFFFFB + i)
}

#test
{
    var wide: [3] u64
    unsigned64(&wide[0])
    for i in 3 do
        Swag.assert(wide[i] == 0xFFFFFFFFFFFFFFF9 + 2 * cast(u64, i))

    var signed: [3] s64
    signed64(&signed[0])
    for i in 3 do
        Swag.assert(signed[i] == 0x7FFFFFFFFFFFFFF9 + 2 * cast(s64, i))
}

#test
{
    var values: [4] s32
    signed32(&values[0])
    for i in 4 do
        Swag.assert(values[i] == -4 + 2 * cast(s32, i))
    let sum = highSum()
    Swag.assert(sum == 0xFFFFFFFFFFFFFFF2)
}
