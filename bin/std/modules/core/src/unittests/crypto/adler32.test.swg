#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag

func adler32Reference(buffer: const [..] u8)->u32
{
    const Base = 65521'u32
    var s1 = 1'u32
    var s2 = 0'u32

    for value in buffer
    {
        s1 = (s1 + cast(u32) value) % Base
        s2 = (s2 + s1) % Base
    }

    return s1 | (s2 << 16)
}

func assertAdler32(buffer: const [..] u8)
{
    let expected = adler32Reference(buffer)

    @assert(Hash.Adler32.compute(buffer) == expected)

    var adler: Hash.Adler32
    adler.init()
    adler.update(buffer)
    @assert(adler.adler == expected)

    adler.init()
    adler.update("")
    adler.update(buffer)
    @assert(adler.adler == expected)
}

func fillAdlerPattern(buffer: [..] u8)
{
    var i = 0'u64
    while i < @countof(buffer)
    {
        buffer[i] = cast(u8) ((i * 37 + 11) & 0xFF)
        i         += 1
    }
}

#test
{
    @assert(Hash.Adler32.compute("") == 1'u32)
    @assert(Hash.Adler32.compute("a") == 0x00620062'u32)
    @assert(Hash.Adler32.compute("abc") == 0x024D0127'u32)
    @assert(Hash.Adler32.compute("Wikipedia") == 0x11E60398'u32)

    assertAdler32("")
    assertAdler32("a")
    assertAdler32("123456789012345")
    assertAdler32("1234567890123456")
    assertAdler32("12345678901234567")

    var adler: Hash.Adler32
    adler.update("dirty")
    adler.init()
    @assert(adler.adler == 1'u32)

    var data: [11121] u8
    fillAdlerPattern(data)

    for [length] in 65
    {
        assertAdler32(data[until length])
    }

    assertAdler32(data[until 255])
    assertAdler32(data[until 256])
    assertAdler32(data[until 5551])
    assertAdler32(data[until 5552])
    assertAdler32(data[until 5553])
    assertAdler32(data[until 11104])
    assertAdler32(data[until 11121])

    var split: Hash.Adler32
    split.init()
    split.update(data[until 1])
    split.update(data[1 until 16])
    split.update(data[16 until 5552])
    split.update(data[5552 until 11121])
    @assert(split.adler == Hash.Adler32.compute(data))
}
