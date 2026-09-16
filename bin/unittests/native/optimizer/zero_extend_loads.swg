#global private

struct NarrowValues
{
    byte: u8
    word: u16
}

#[Swag.NoInline]
func loadByte(value: *NarrowValues)->u64 => value.byte

#[Swag.NoInline]
func loadWord(value: *NarrowValues)->u64 => value.word

#[Swag.NoInline]
func indexedByte(values: [*]u8, index: u64)->u64 => values[index]

#[Swag.NoInline]
func indexedWord(values: [*]u16, index: u64)->u64 => values[index]

#[Swag.NoInline]
func keepNarrowArguments(a, b, c, d, e, f: u16)->u64
{
    return cast(u64) a + cast(u64) b + cast(u64) c + cast(u64) d + cast(u64) e + cast(u64) f
}

#test
{
    var value = NarrowValues{byte: 255, word: 65535}
    Swag.assert(loadByte(&value) == 255)
    Swag.assert(loadWord(&value) == 65535)
    var bytes = [0'u8, 127, 128, 255]
    var words = [0'u16, 32767, 32768, 65535]
    for i in 4'u64
    {
        Swag.assert(indexedByte(&bytes[0], i) == bytes[i])
        Swag.assert(indexedWord(&words[0], i) == words[i])
    }
    Swag.assert(keepNarrowArguments(1, 128, 255, 32768, 65535, 65535) == 164222)
}
