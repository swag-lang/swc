#global private

#[Swag.NoInline, Swag.Optimize(false), Swag.Safety(.Overflow, false)]
func reference(words: const [*] u64, index, seed: u64)->[3] u64
{
    return [(seed + words[index]) & 0xFFFFFFFF, (seed - words[index + 1]) & 0xFFFF, (seed * words[index + 2]) & 0xFFFFFFFF]
}

#[Swag.NoInline, Swag.Optimize(true), Swag.Safety(.Overflow, false)]
func optimized(words: const [*] u64, index, seed: u64)->[3] u64
{
    return [(seed + words[index]) & 0xFFFFFFFF, (seed - words[index + 1]) & 0xFFFF, (seed * words[index + 2]) & 0xFFFFFFFF]
}

#[Swag.NoInline, Swag.Optimize(false), Swag.Safety(.Overflow, false)]
func aliasReference(words: [*] u64, index, other, replacement, seed: u64)->u64
{
    let loaded = words[index]
    words[other] = replacement
    return ((seed + loaded) & 0xFFFFFFFF) ^ words[other]
}

#[Swag.NoInline, Swag.Optimize(true), Swag.Safety(.Overflow, false)]
func aliasOptimized(words: [*] u64, index, other, replacement, seed: u64)->u64
{
    let loaded = words[index]
    words[other] = replacement
    return ((seed + loaded) & 0xFFFFFFFF) ^ words[other]
}

#test
{
    let words = [0'u64, 1, 0x7FFF, 0xFFFF, 0xFFFFFFFF, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    for seed in [0'u64, 1, 0x123456789ABCDEF0, 0xFFFFFFFFFFFFFFFF]
    {
        for index in 5'u64
        {
            let expected = reference(words.buffer, index, seed)
            let actual   = optimized(words.buffer, index, seed)
            for lane in 3 do
                Swag.require(actual[lane] == expected[lane])
        }

        for index in 3'u64
        {
            for other in 3'u64
            {
                var expectedWords = words
                var actualWords   = words
                let expected      = aliasReference(expectedWords.buffer, index, other, seed, 0x1122334455667788)
                let actual        = aliasOptimized(actualWords.buffer, index, other, seed, 0x1122334455667788)
                Swag.require(actual == expected)
                for lane in 7 do
                    Swag.require(actualWords[lane] == expectedWords[lane])
            }
        }
    }
}
