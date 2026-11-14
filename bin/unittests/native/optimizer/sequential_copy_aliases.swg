#global private

#[Swag.NoInline, Swag.Optimize(false)]
func referenceWords(target, source: [*] u64)
{
    for index in 8'u64 do
        target[index] = source[index]
}

#[Swag.NoInline, Swag.Optimize(true)]
func optimizedWords(target, source: [*] u64)
{
    for index in 8'u64 do
        target[index] = source[index]
}

#[Swag.NoInline, Swag.Optimize(false)]
func referenceHalves(target, source: [*] u32)
{
    for index in 16'u64 do
        target[index] = source[index]
}

#[Swag.NoInline, Swag.Optimize(true)]
func optimizedHalves(target, source: [*] u32)
{
    for index in 16'u64 do
        target[index] = source[index]
}

#[Swag.NoInline, Swag.Optimize(false)]
func referenceLive(target, source: [*] u64)->u64
{
    let first = source[0]
    target[0] = first
    for index in 1'u64 until 9 do
        target[index] = source[index]
    return first
}

#[Swag.NoInline, Swag.Optimize(true)]
func optimizedLive(target, source: [*] u64)->u64
{
    let first = source[0]
    target[0] = first
    for index in 1'u64 until 9 do
        target[index] = source[index]
    return first
}

#test
{
    for seed in [0'u64, 1, 17, 255]
    {
        for source in [64'u64, 65, 71]
        {
            for target in 48'u64 until 112
            {
                var expected, actual: [256] u8
                for index in 256'u64
                {
                    expected[index] = cast(u8, (index * 37 + seed * 13) & 255)
                    actual[index]   = expected[index]
                }

                referenceWords(cast([*] u64, expected.buffer + target), cast([*] u64, expected.buffer + source))
                optimizedWords(cast([*] u64, actual.buffer + target), cast([*] u64, actual.buffer + source))
                Swag.require(actual == expected)
                referenceHalves(cast([*] u32, expected.buffer + target), cast([*] u32, expected.buffer + source))
                optimizedHalves(cast([*] u32, actual.buffer + target), cast([*] u32, actual.buffer + source))
                Swag.require(actual == expected)
                let firstExpected = referenceLive(cast([*] u64, expected.buffer + target), cast([*] u64, expected.buffer + source))
                let firstActual   = optimizedLive(cast([*] u64, actual.buffer + target), cast([*] u64, actual.buffer + source))
                Swag.require(firstActual == firstExpected)
                Swag.require(actual == expected)
            }
        }
    }
}
