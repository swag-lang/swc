#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.NoInline]
func sumBytes(values: const [*] u8, count: u64, total: u32)->u32
{
    var result = total
    for index in count do
        result += values[index + 1]
    return result
}

#[Swag.NoInline]
func sumWords(values: const [*] u32, count: u64, total: u64)->u64
{
    var result = total
    for index in count do
        result += values[index]
    return result
}

#[Swag.NoInline]
func sumQwords(values: const [*] u64, count: u64, total: u64)->u64
{
    var result = total
    for index in count do
        result += values[index]
    return result
}

#[Swag.NoInline]
func sumSignedBytes(values: const [*] u8, origin, count: s32, total: u32)->u32
{
    var result = total
    for index in count do
        result += values[origin + index]
    return result
}

#test
{
    var bytes:  [66] u8
    var words:  [65] u32
    var qwords: [65] u64
    for index in words.count
    {
        bytes[index + 1] = cast(u8, index * 19 + 11)
        words[index]     = 0xFFFF_FFFF'u32 - cast(u32, index * 97)
        qwords[index]    = 0xFFFF_FFFF_FFFF_0000'u64 + index * 997
    }

    const ByteSeed = 0xFFFF_FFE0'u32
    const WordSeed = 0xFFFF_FFFF_FFFF_FFE0'u64
    var byteSum  = ByteSeed
    var wordSum  = WordSeed
    var qwordSum = WordSeed
    for count in words.count + 1
    {
        Swag.require(sumBytes(&bytes[0], count, ByteSeed) == byteSum)
        Swag.require(sumWords(&words[0], count, WordSeed) == wordSum)
        Swag.require(sumQwords(&qwords[0], count, WordSeed) == qwordSum)
        if count < words.count
        {
            byteSum  += bytes[count + 1]
            wordSum  += words[count]
            qwordSum += qwords[count]
        }
    }
}

#test
{
    var bytes: [129] u8
    for &value, index in bytes do
        value[] = cast(u8, index * 29 + 17)

    const Seed = 0xFFFF_FFF0'u32
    let center = &bytes[48]
    for origin in -16's32 until 17
    {
        Swag.require(sumSignedBytes(center, origin, -2, Seed) == Seed)
        var expected = Seed
        for count in 65's32
        {
            Swag.require(sumSignedBytes(center, origin, count, Seed) == expected)
            expected += bytes[48 + origin + count]
        }
    }
}
