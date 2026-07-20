#global #if #command == Swag.CompilerCommand.Test
#global private
using Swag

#[Swag.Safety(.Overflow, false)]
func crc64Reference(buffer: #nonull const [..] u8, kind: Hash.Crc64Kind)->u64
{
    var crc: u64

    #[Swag.Complete]
    switch kind
    {
    case Hash.Crc64Kind.ECMA182:
        const Poly = 0x42F0_E1EB_A9EA_3693'u64
        for value in buffer
        {
            crc ^= cast(u64) value << 56
            for bit in 8
            {
                if crc & 0x8000_0000_0000_0000'u64 do
                    crc = (crc << 1) ^ Poly
                else do
                    crc <<= 1
            }
        }
        return crc

    case Hash.Crc64Kind.ISO:
        const Poly = 0xD800_0000_0000_0000'u64
        crc = ~crc
        for value in buffer
        {
            crc ^= value
            for bit in 8
            {
                if crc & 1 do
                    crc = (crc >> 1) ^ Poly
                else do
                    crc >>= 1
            }
        }
        return ~crc

    case Hash.Crc64Kind.ISOXZ:
        const Poly = 0xC96C_5795_D787_0F42'u64
        crc = ~crc
        for value in buffer
        {
            crc ^= value
            for bit in 8
            {
                if crc & 1 do
                    crc = (crc >> 1) ^ Poly
                else do
                    crc >>= 1
            }
        }
        return ~crc
    }
}

func assertCrc64Kind(buffer: #nonull const [..] u8, kind: Hash.Crc64Kind)
{
    let expected = crc64Reference(buffer, kind)

    @assert(Hash.Crc64.compute(buffer, kind) == expected)

    var crc: Hash.Crc64
    crc.init(kind)
    crc.update(buffer, kind)
    @assert(crc.crc == expected)

    crc.update("", kind)
    @assert(crc.crc == expected)
}

func assertCrc64(buffer: #nonull const [..] u8)
{
    assertCrc64Kind(buffer, Hash.Crc64Kind.ECMA182)
    assertCrc64Kind(buffer, Hash.Crc64Kind.ISO)
    assertCrc64Kind(buffer, Hash.Crc64Kind.ISOXZ)
}

func fillCrc64Pattern(buffer: #nonull [..] u8)
{
    var i = 0'u64
    while i < @countof(buffer)
    {
        buffer[i] = cast(u8) ((i * 109 + 41) & 0xff)
        i += 1
    }
}

#test
{
    @assert(Hash.Crc64.compute("") == 0'u64)
    @assert(Hash.Crc64.compute("123456789") == 0x6C40_DF5F_0B49_7347'u64)
    @assert(Hash.Crc64.compute("123456789", Hash.Crc64Kind.ISO) == 0xB909_56C7_75A4_1001'u64)
    @assert(Hash.Crc64.compute("123456789", Hash.Crc64Kind.ISOXZ) == 0x995D_C9BB_DF19_39FA'u64)

    assertCrc64("")
    assertCrc64("a")
    assertCrc64("abc")
    assertCrc64("123456789")

    var data: [257] u8
    fillCrc64Pattern(data)

    for length in 130
    {
        assertCrc64(data[until length])
    }

    assertCrc64(data[until 255])
    assertCrc64(data[until 256])
    assertCrc64(data[until 257])
    assertCrc64(data[1 until 130])

    var split: Hash.Crc64
    split.init(Hash.Crc64Kind.ISOXZ)
    split.update(data[until 1], Hash.Crc64Kind.ISOXZ)
    split.update(data[1 until 64], Hash.Crc64Kind.ISOXZ)
    split.update(data[64 until 129], Hash.Crc64Kind.ISOXZ)
    split.update(data[129 until 257], Hash.Crc64Kind.ISOXZ)
    @assert(split.crc == Hash.Crc64.compute(data, Hash.Crc64Kind.ISOXZ))
}
