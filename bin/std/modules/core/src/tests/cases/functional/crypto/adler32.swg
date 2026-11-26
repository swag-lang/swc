#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func adler32Reference(buffer: const [..] u8)->u32
{
    const Base = 65521_u32
    var s1 = 1_u32
    var s2 = 0_u32

    for value in buffer
    {
        s1 = (s1 + cast(u32, value)) % Base
        s2 = (s2 + s1) % Base
    }

    return s1 | (s2 << 16)
}

func assertAdler32(buffer: const [..] u8)
{
    let expected = adler32Reference(buffer)

    Swag.require(Hash.Adler32.compute(buffer) == expected)

    var adler: Hash.Adler32
    adler.reset()
    adler.update(buffer)
    Swag.require(adler.value() == expected)

    adler.reset()
    adler.update("")
    adler.update(buffer)
    Swag.require(adler.value() == expected)
}

func fillAdlerPattern(buffer: [..] u8)
{
    var i = 0_u64
    while i < buffer.count
    {
        buffer[i] = cast(u8, ((i * 37 + 11) & 0xFF))
        i         += 1
    }
}

#test
{
    Swag.require(Hash.Adler32.compute("") == 1_u32)
    Swag.require(Hash.Adler32.compute("a") == 0x00620062_u32)
    Swag.require(Hash.Adler32.compute("abc") == 0x024D0127_u32)
    Swag.require(Hash.Adler32.compute("Wikipedia") == 0x11E60398_u32)

    assertAdler32("")
    assertAdler32("a")
    assertAdler32("123456789012345")
    assertAdler32("1234567890123456")
    assertAdler32("12345678901234567")

    var adler: Hash.Adler32
    adler.update("dirty")
    adler.reset()
    Swag.require(adler.value() == 1_u32)

    var data: [11121] u8
    fillAdlerPattern(data)

    for length in 130
    {
        assertAdler32(data[until length])
    }

    assertAdler32(data[until 255])
    assertAdler32(data[until 256])
    assertAdler32(data[until 5503])
    assertAdler32(data[until 5504])
    assertAdler32(data[until 5505])
    assertAdler32(data[until 5551])
    assertAdler32(data[until 5552])
    assertAdler32(data[until 5553])
    assertAdler32(data[until 11104])
    assertAdler32(data[until 11121])

    var split: Hash.Adler32
    split.reset()
    split.update(data[until 1])
    split.update(data[1 until 16])
    split.update(data[16 until 5552])
    split.update(data[5552 until 11121])
    Swag.require(split.value() == Hash.Adler32.compute(data))

    for index in data.count
    {
        data[index] = 0xFF

        // Worst-case weighted sums around the one-shot reduction threshold.
    }

    assertAdler32(data[1 until 23])
    assertAdler32(data[1 until 24])
    assertAdler32(data[1 until])

    split.reset()
    split.update(data[1 until 257])
    split.update(data[257 until])
    Swag.require(split.value() == adler32Reference(data[1 until]))
}

#[Swag.TestTag("stress")]
#test
{
    const TileBytes = 512 * 1024
    const PrefixBytes = 37
    const Sizes = [4 * TileBytes - 1, 4 * TileBytes, 4 * TileBytes + 1,
                   4 * TileBytes + 79, 4 * TileBytes + 80, 33 * TileBytes + 15]
    var storage: Array'u8
    storage.resize(33 * TileBytes + 15 + PrefixBytes + 7)
    for index in storage.count do
        storage[index] = cast(u8, (((index ^ (index >> 8) ^ (index >> 14)) * 47 + 13) & 0xFF))

    for size in Sizes
    {
        let input = storage.toSlice()[7 until size + PrefixBytes + 7]
        var serial: Hash.Adler32
        serial.reset()
        var offset = 0'u64
        while offset < input.count
        {
            let end = Math.min(offset + TileBytes - 7, input.count)
            serial.update(input[offset until end])
            offset = end
        }

        var checksum: Hash.Adler32
        checksum.reset()
        checksum.update(input[until PrefixBytes])
        checksum.update(input[PrefixBytes until])
        Swag.require(checksum.value() == serial.value())
    }
}
