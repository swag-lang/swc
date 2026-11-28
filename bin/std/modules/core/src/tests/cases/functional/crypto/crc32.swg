#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#[Swag.Safety(.Overflow, false)]
func crc32Reference(buffer: const [..] u8, seed: u32 = 0)->u32
{
    var crc = ~seed

    for value in buffer
    {
        crc ^= cast(u32, value)
        for 8
        {
            if crc & 1
            {
                crc = (crc >> 1) ^ 0xEDB88320_u32
            }
            else
            {
                crc >>= 1
            }
        }
    }

    return ~crc
}

func assertCrc32(buffer: const [..] u8, seed: u32 = 0)
{
    let expected = crc32Reference(buffer, seed)

    if not seed
    {
        Swag.require(Hash.Crc32.compute(buffer) == expected)
    }

    var crc: Hash.Crc32
    crc.reset(seed)
    crc.update(buffer)
    Swag.require(crc.value() == expected)

    crc.update("")
    Swag.require(crc.value() == expected)
}

func fillCrc32Pattern(buffer: [..] u8)
{
    var i = 0_u64
    while i < buffer.count
    {
        buffer[i] = cast(u8, ((i * 73 + 19) & 0xFF))
        i         += 1
    }
}

#test
{
    Swag.require(Hash.Crc32.compute("") == 0_u32)
    Swag.require(Hash.Crc32.compute("123456789") == 0xCBF43926_u32)

    assertCrc32("")
    assertCrc32("a")
    assertCrc32("abc")
    assertCrc32("123456789")

    var crc: Hash.Crc32
    crc.reset(0x12345678)
    crc.update("dirty")
    crc.reset()
    Swag.require(crc.value() == 0_u32)

    var data: [257] u8
    fillCrc32Pattern(data)

    for length in 130
    {
        assertCrc32(data[until length])
    }

    assertCrc32(data[until 255])
    assertCrc32(data[until 256])
    assertCrc32(data[until 257])
    assertCrc32(data[1 until 130])

    // Exercise 128 folded bytes from an unaligned address, followed by a one-byte tail.
    assertCrc32(data[1 until 130], 0x12345678)

    for length in 32 until 96
    {
        assertCrc32(data[1 until 1 + length], 0x12345678)
    }

    var split: Hash.Crc32
    split.reset()
    split.update(data[until 1])
    split.update(data[1 until 64])
    split.update(data[64 until 129])
    split.update(data[129 until 257])
    Swag.require(split.value() == Hash.Crc32.compute(data))

    assertCrc32(data[until 257], 0x12345678)

    var seeded: Hash.Crc32
    seeded.reset(0x12345678)
    seeded.update(data[until 128])
    seeded.update(data[128 until 257])
    Swag.require(seeded.value() == crc32Reference(data, 0x12345678))
}

#test
{
    let seed = 0x1234_5678_u32
    var data: [4391] u8
    fillCrc32Pattern(data)

    for size in [1023, 1024, 1025, 1151, 1152, 1153, 2048, 2063, 4095, 4096, 4097, 4351, 4352, 4353]
    {
        assertCrc32(data[7 until 7 + size], seed)
    }

    let input = data[1 until]
    var split: Hash.Crc32
    split.reset(seed)
    split.update(input[until 37])
    split.update(input[37 until])
    Swag.require(split.value() == crc32Reference(input, seed))
}

#[Swag.TestTag("stress")]
#test
{
    const TileBytes = 512 * 1024
    const PrefixBytes = 37
    const Sizes       = [8 * TileBytes - 1, 8 * TileBytes, 8 * TileBytes + 1,
                         8 * TileBytes + 79, 8 * TileBytes + 80, 33 * TileBytes + 15]
    var storage: Array!{u8}
    storage.resize(33 * TileBytes + 15 + PrefixBytes + 7)
    for index in storage.count
    {
        storage[index] = cast(u8, (((index ^ (index >> 8) ^ (index >> 14)) * 47 + 13) & 0xFF))
    }

    for size in Sizes
    {
        let input = storage.toSlice()[7 until size + PrefixBytes + 7]
        var serial: Hash.Crc32
        serial.reset(0x1234_5678_u32)
        var offset = 0_u64
        while offset < input.count
        {
            let end = Math.min(offset + TileBytes - 7, input.count)
            serial.update(input[offset until end])
            offset = end
        }

        var checksum: Hash.Crc32
        checksum.reset(0x1234_5678_u32)
        checksum.update(input[until PrefixBytes])
        checksum.update(input[PrefixBytes until])
        Swag.require(checksum.value() == serial.value())
    }
}
