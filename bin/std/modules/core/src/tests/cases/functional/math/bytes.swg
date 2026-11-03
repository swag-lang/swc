#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    #assert(Math.make16(0x12, 0x34) == 0x1234)
    #assert(Math.make32(0x1234, 0x5678) == 0x12345678)
    #assert(Math.make32(0x12, 0x34, 0x56, 0x78) == 0x12345678)
    #assert(Math.make64(0x12345678, 0x9ABCDEF0) == 0x12345678_9ABCDEF0)
    #assert(Math.byteAt(0x12345678'u32, 0) == 0x78)
    #assert(Math.byteAt(0x12345678'u32, 3) == 0x12)

    Swag.assert(Math.make16(0, 0) == 0)
    Swag.assert(Math.make16(0xFF, 0xFF) == 0xFFFF)
    Swag.assert(Math.make32(0, 0) == 0)
    Swag.assert(Math.make32(0xFFFF, 0xFFFF) == 0xFFFFFFFF)
    Swag.assert(Math.make32(0xFF, 0xFF, 0xFF, 0xFF) == 0xFFFFFFFF)
}

#test
{
    let bytes: [8] u8 = [0xEF, 0xCD, 0xAB, 0x89, 0x67, 0x45, 0x23, 0x01]
    let value         = 0x01234567_89ABCDEF'u64
    for index in 8 do
        Swag.assert(Math.byteAt(value, index) == bytes[index])

    for index in 4 do
        Swag.assert(Math.byteAt(0x89ABCDEF'u32, index) == bytes[index])
    for index in 2 do
        Swag.assert(Math.byteAt(0xCDEF'u16, index) == bytes[index])
    Swag.assert(Math.byteAt(0xEF'u8, 0) == bytes[0])
}

#test
{
    // Exercise each byte value in each position, including the high bit of every width.
    for value in 256
    {
        let byte = cast(u8, value)
        Swag.assert(Math.byteAt(byte, 0) == byte)
        Swag.assert(Math.byteAt(Math.make16(byte, 0), 1) == byte)
        Swag.assert(Math.byteAt(Math.make16(0, byte), 0) == byte)

        let words: [4] u32 = [Math.make32(byte, 0, 0, 0), Math.make32(0, byte, 0, 0),
                              Math.make32(0, 0, byte, 0), Math.make32(0, 0, 0, byte)]
        for index in 4
        {
            Swag.assert(Math.byteAt(words[index], 3 - index) == byte)
            let rebuilt = Math.make32(Math.byteAt(words[index], 3),
                                      Math.byteAt(words[index], 2),
                                      Math.byteAt(words[index], 1),
                                      Math.byteAt(words[index], 0))
            Swag.assert(rebuilt == words[index])
        }

        for index in 8
        {
            let wide = cast(u64, byte) << (index * 8)
            Swag.assert(Math.byteAt(wide, index) == byte)
        }
    }
}
