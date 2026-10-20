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

#[Swag.NoInline]
func furtherPrecision(values: [*] s32, output: [*] s64)
{
    var low         = 0's64
    var wideDivisor = 0's64
    for i in 0's64 until 57
    {
        let weight = cast(s64, values[i])
        low         += weight * (i % 1000) + i / 1000
        wideDivisor += weight * (i % 0x100000001's64) + i / 0x100000001's64
    }

    var wideCounter = 0's64
    var wideBoth    = 0's64
    let first       = 0x100000001's64
    for i in first until first + 64
    {
        let weight = cast(s64, values[i - first])
        wideCounter += weight * (i % 7) + i / 7
        wideBoth    += weight * (i % 0x100000003's64) + i / 0x100000003's64
    }

    output[0] = low
    output[1] = wideDivisor
    output[2] = wideCounter
    output[3] = wideBoth
}

#[Swag.NoInline, Swag.Optimize(false)]
func referenceBound(values: [*] s32, first, count, divisor: s64)->s64
{
    var result = 0's64
    for i in first until first + count do
        result += cast(s64, values[i - first]) * (i % divisor) + i / divisor
    return result
}

#test
{
    var values: [64] s32
    for i in 64 do
        values[i] = cast(s32, (i * 19) % 47) - 23

    var actual: [4] s64
    furtherPrecision(&values[0], &actual[0])
    Swag.assert(actual[0] == referenceBound(&values[0], 0, 57, 1000))
    Swag.assert(actual[1] == referenceBound(&values[0], 0, 57, 0x100000001))
    Swag.assert(actual[2] == referenceBound(&values[0], 0x100000001, 64, 7))
    Swag.assert(actual[3] == referenceBound(&values[0], 0x100000001, 64, 0x100000003))
}
