#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag

func fillCity32Pattern(buffer: [..] u8)
{
    var i = 0'u64
    while i < @countof(buffer)
    {
        buffer[i] = cast(u8) ((i * 73 + 19) & 0xFF)
        i         += 1
    }
}

func assertCity32(buffer: const [..] u8, expected: u32)
{
    @assert(Hash.City32.compute(buffer) == expected)

    var city: Hash.City32
    city.init()
    city.update(buffer)
    @assert(city.crc == expected)
}

#test
{
    @assert(Hash.City32.compute("") == 0xDC56D17A'u32)
    @assert(Hash.City32.compute("a") == 0x3C973D4D'u32)
    @assert(Hash.City32.compute("abc") == 0x2F635EC7'u32)
    @assert(Hash.City32.compute("123456789012") == 0xC522AB0F'u32)
    @assert(Hash.City32.compute("1234567890123") == 0x11BC2118'u32)
    @assert(Hash.City32.compute("123456789012345678901234") == 0x088921D1'u32)
    @assert(Hash.City32.compute("1234567890123456789012345") == 0x60CACDAD'u32)

    var city: Hash.City32
    city.update("dirty")
    city.init()
    @assert(city.crc == 0'u32)

    city.crc = 0x12345678'u32
    city.update("abc")
    @assert(city.crc == 0xD30EC8CC'u32)

    const expected: [81] u32 = [
        0xDC56D17A, 0x58F6C2CD, 0x971FA0E9, 0x50B13F74, 0x8B94C7AB, 0xCC8588FC, 0x97C13711, 0x7AE4CC55,
        0x650D349C, 0x08D564E4, 0x3DD52F1D, 0x844EE8D7, 0xA4EADC0D, 0xF8FC98B5, 0xCB0BA276, 0x9892C4F6,
        0x2320B3FF, 0x39927874, 0x675B64F3, 0xCBBDBEF3, 0x8DE1675B, 0xC413F07F, 0x916A7CFE, 0x2AA39DFA,
        0x13BE1C05, 0xE8C506EA, 0x8785B3E4, 0x4398DB7D, 0xC3ADE094, 0x387F7870, 0xCA9DC110, 0x5589B326,
        0xC92C65D2, 0x00FEC97C, 0xA3523990, 0x00877F2A, 0x589A7104, 0x60F18E9C, 0xF5557E09, 0xE1D26156,
        0xB4E122E1, 0x817EDD10, 0x328F0E80, 0xA3DAADCF, 0x7B9E1F8D, 0xE07A0042, 0x148C3142, 0x9B9A343E,
        0x9021F2C8, 0x2DD862F6, 0xEA6F0CD6, 0x66AA27C0, 0x52A01025, 0x8CE8FC50, 0x029AE255, 0x08F72712,
        0xE9ED4448, 0xE2154B06, 0x14E87E4B, 0xD4523644, 0x4EA67CA0, 0x1D4E3727, 0x335BB0A5, 0x4E7CC531,
        0xCEE22CF9, 0x33D02DC8, 0xED16FDA8, 0x31312560, 0x55C19AE4, 0x7DB8D079, 0x3D280229, 0x2B2765DC,
        0x521295AD, 0x44266C93, 0x7157544E, 0x26B7CD38, 0x52EFAE99, 0xA90120A4, 0xDEF646C1, 0x35C1A025,
        0x47ABEE44]

    var data: [80] u8
    fillCity32Pattern(data)

    for length in @countof(expected)
    {
        assertCity32(data[until length], expected[length])
    }
}
