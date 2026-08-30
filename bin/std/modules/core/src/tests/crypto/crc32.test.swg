#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#[Swag.Safety(.Overflow, false)]
func crc32Reference(buffer: const [..] u8, seed: u32 = 0)->u32
{
    var crc = ~seed

    for value in buffer
    {
        crc ^= cast(u32) value
        for bit in 8
        {
            if crc & 1 do
                crc = (crc >> 1) ^ 0xEDB88320'u32
            else do
                crc >>= 1
        }
    }

    return ~crc
}

func assertCrc32(buffer: const [..] u8, seed: u32 = 0)
{
    let expected = crc32Reference(buffer, seed)

    if !seed do
        Swag.assert(Hash.Crc32.compute(buffer) == expected)

    var crc: Hash.Crc32
    crc.reset(seed)
    crc.update(buffer)
    Swag.assert(crc.value() == expected)

    crc.update("")
    Swag.assert(crc.value() == expected)
}

func fillCrc32Pattern(buffer: [..] u8)
{
    var i = 0'u64
    while i < buffer.count
    {
        buffer[i] = cast(u8) ((i * 73 + 19) & 0xFF)
        i         += 1
    }
}

#test
{
    Swag.assert(Hash.Crc32.compute("") == 0'u32)
    Swag.assert(Hash.Crc32.compute("123456789") == 0xCBF43926'u32)

    assertCrc32("")
    assertCrc32("a")
    assertCrc32("abc")
    assertCrc32("123456789")

    var crc: Hash.Crc32
    crc.reset(0x12345678)
    crc.update("dirty")
    crc.reset()
    Swag.assert(crc.value() == 0'u32)

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

    var split: Hash.Crc32
    split.reset()
    split.update(data[until 1])
    split.update(data[1 until 64])
    split.update(data[64 until 129])
    split.update(data[129 until 257])
    Swag.assert(split.value() == Hash.Crc32.compute(data))

    assertCrc32(data[until 257], 0x12345678)

    var seeded: Hash.Crc32
    seeded.reset(0x12345678)
    seeded.update(data[until 128])
    seeded.update(data[128 until 257])
    Swag.assert(seeded.value() == crc32Reference(data, 0x12345678))
}
