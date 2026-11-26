#global if #command == Swag.CompilerCommand.Test
#global private

#[Swag.TestTag("stress")]
#test
{
    const TileBytes = 512 * 1024
    const Sizes     = [4 * TileBytes - 1, 4 * TileBytes, 4 * TileBytes + 15, 4 * TileBytes + 64, 33 * TileBytes + 65]
    const Variants  = [Hash.Crc64Kind.Ecma182, .Iso, .IsoXz]
    var storage: Array'u8
    storage.resize(33 * TileBytes + 72)
    for index in storage.count do
        storage[index] = cast(u8, (((index ^ (index >> 8) ^ (index >> 14)) * 47 + 13) & 0xFF))

    for kind in Variants
    {
        for size in Sizes
        {
            let input = storage.toSlice()[7 until size + 7]
            var serial: Hash.Crc64
            serial.reset(kind)
            var offset = 0'u64
            while offset < input.count
            {
                let end = Math.min(offset + TileBytes - 7, input.count)
                serial.update(input[offset until end])
                offset = end
            }

            let expected = serial.value()
            Swag.require(Hash.Crc64.compute(input, kind) == expected)

            var seeded: Hash.Crc64
            seeded.reset(kind)
            seeded.update(input[until 37])
            seeded.update(input[37 until])
            Swag.require(seeded.value() == expected)
        }
    }
}
