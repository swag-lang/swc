#global private

#[Swag.NoInline]
func positive32(values: [*] s32)->s64
{
    var result = 0's64
    for i in 0's32 until 57 do
        result += cast(s64, values[i + 7]) * (i % 7)
    return result
}

#[Swag.NoInline]
func positive64(values: [*] s32)->s64
{
    var result = 0's64
    for i in 0's64 until 57 do
        result += cast(s64, values[i + 7]) * (i % 7)
    return result
}

#[Swag.NoInline]
func negative32(values: [*] s32)->s64
{
    var result = 0's64
    for i in -7's32 until 57 do
        result += cast(s64, values[i + 7]) * (i % 7)
    return result
}

#[Swag.NoInline]
func negative64(values: [*] s32)->s64
{
    var result = 0's64
    for i in -7's64 until 57 do
        result += cast(s64, values[i + 7]) * (i % 7)
    return result
}

#[Swag.NoInline]
func unsigned32Boundary(values: [*] s32)->s64
{
    var result  = 0's64
    let first   = 0xFFFFFFFF's64 - 96
    let divisor = 0xFFFFFFFF's64 - 64
    for i in first until first + 64 do
        result += cast(s64, values[i - first]) * (i % divisor) + i / divisor
    return result
}

#[Swag.NoInline, Swag.Optimize(false)]
func referenceUnsigned32Boundary(values: [*] s32)->s64
{
    var result  = 0's64
    let first   = 0xFFFFFFFF's64 - 96
    let divisor = 0xFFFFFFFF's64 - 64
    for i in first until first + 64 do
        result += cast(s64, values[i - first]) * (i % divisor) + i / divisor
    return result
}

#[Swag.NoInline, Swag.Optimize(false)]
func reference(values: [*] s32, start: s64)->s64
{
    var result = 0's64
    for i in start until 57 do
        result += cast(s64, values[i + 7]) * (i % 7)
    return result
}

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func boundary32()->s32
{
    var value  = 0x7FFFFFFD's32
    var result = 0's32
    for 8
    {
        result += value % 7
        value  += 1
    }
    return result
}

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func boundary64()->s64
{
    var value  = 0x7FFFFFFFFFFFFFFD's64
    var result = 0's64
    for 8
    {
        result += value % 7
        value  += 1
    }
    return result
}

#[Swag.NoInline, Swag.Optimize(false), Swag.Safety(.Overflow, false)]
func referenceBoundary32()->s32
{
    var value  = 0x7FFFFFFD's32
    var result = 0's32
    for 8
    {
        result += value % 7
        value  += 1
    }
    return result
}

#[Swag.NoInline, Swag.Optimize(false), Swag.Safety(.Overflow, false)]
func referenceBoundary64()->s64
{
    var value  = 0x7FFFFFFFFFFFFFFD's64
    var result = 0's64
    for 8
    {
        result += value % 7
        value  += 1
    }
    return result
}

#test
{
    var values: [64] s32
    for i in 64 do
        values[i] = cast(s32, (i * 17) % 43) - 21

    Swag.assert(positive32(&values[0]) == reference(&values[0], 0))
    Swag.assert(positive64(&values[0]) == reference(&values[0], 0))
    Swag.assert(negative32(&values[0]) == reference(&values[0], -7))
    Swag.assert(negative64(&values[0]) == reference(&values[0], -7))
    Swag.assert(unsigned32Boundary(&values[0]) == referenceUnsigned32Boundary(&values[0]))
    Swag.assert(boundary32() == referenceBoundary32())
    Swag.assert(boundary64() == referenceBoundary64())
}
