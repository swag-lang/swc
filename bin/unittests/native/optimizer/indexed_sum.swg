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

#test
{
    var bytes: [66] u8
    var words: [65] u32
    for index in words.count
    {
        bytes[index + 1] = cast(u8, index * 19 + 11)
        words[index]     = 0xFFFF_FFFF'u32 - cast(u32, index * 97)
    }

    const ByteSeed = 0xFFFF_FFE0'u32
    const WordSeed = 0xFFFF_FFFF_FFFF_FFE0'u64
    var byteSum = ByteSeed
    var wordSum = WordSeed
    for count in words.count + 1
    {
        Swag.require(sumBytes(&bytes[0], count, ByteSeed) == byteSum)
        Swag.require(sumWords(&words[0], count, WordSeed) == wordSum)
        if count < words.count
        {
            byteSum += bytes[count + 1]
            wordSum += words[count]
        }
    }
}
