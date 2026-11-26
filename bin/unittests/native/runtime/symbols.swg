#global private

using Swag

func writeDebugU32(bytes: [..] u8, offset: u32, value: u32)
{
    for index in 4 do
        bytes[offset + index] = cast(u8, ((value >> (index * 8)) & 0xFF))
}

func validDebugTable()->[64] u8
{
    var bytes: #returntype
    writeDebugU32(bytes, 0, 0x4244_5753)
    writeDebugU32(bytes, 4, 1)
    writeDebugU32(bytes, 8, 1)
    writeDebugU32(bytes, 12, 36)
    writeDebugU32(bytes, 16, 0x1000)
    writeDebugU32(bytes, 20, 16)
    writeDebugU32(bytes, 24, 36)
    writeDebugU32(bytes, 28, 41)
    writeDebugU32(bytes, 32, 12)
    Swag.memcpy(&bytes[36], "name\0file.swg\0".buffer, 14)
    return bytes
}

func symbolizationFixture()->u32 => 7

#test
{
    var invalid: Swag.AtomicValue'u32
    parallel for |&invalid| 64
    {
        let symbol = Swag.symbolizeStackAddress(cast(*void, &symbolizationFixture))
        if symbol.found and not symbol.name.count do
            invalid.add(1)
    }

    Swag.require(invalid.load() == 0)
}

#test
{
    var bytes = validDebugTable()
    Swag.require(Swag.validateDebugSection(&bytes[0], bytes.count))
    var value = ""
    Swag.require(Swag.readDebugString(&bytes[0], bytes.count, 36, 36, &value) and value == "name")
    Swag.require(Swag.readDebugString(&bytes[0], bytes.count, 36, 0, &value) and value == "")

    writeDebugU32(bytes, 8, Swag.U32.Max)
    Swag.require(not Swag.validateDebugSection(&bytes[0], bytes.count))

    bytes = validDebugTable()
    writeDebugU32(bytes, 24, 20)
    Swag.require(not Swag.validateDebugSection(&bytes[0], bytes.count))

    bytes = validDebugTable()
    writeDebugU32(bytes, 16, 0xFFFF_FFF0)
    writeDebugU32(bytes, 20, 0x30)
    Swag.require(not Swag.validateDebugSection(&bytes[0], bytes.count))

    bytes = validDebugTable()
    writeDebugU32(bytes, 24, 63)
    bytes[63] = 'x'
    Swag.require(not Swag.readDebugString(&bytes[0], bytes.count, 36, 63, &value))
}

#test
{
    let payload: [27] u8 = [
        0xF0, 10,
        0xFF, 3, 16, 112, 120, 24,
        0xC0, 4, 8, 18, 0, 7,
        'o', 'n', 'e', 0, 'f', 'i', 'l', 'e', 0, 't', 'w', 'o', 0]
    var packed: [51] u8
    writeDebugU32(packed, 0, 0x4244_5753)
    writeDebugU32(packed, 4, 5)
    writeDebugU32(packed, 8, 69)
    writeDebugU32(packed, 12, payload.count)
    writeDebugU32(packed, 16, 25)
    writeDebugU32(packed, 20, 2)
    Swag.memcpy(&packed[24], &payload[0], payload.count)

    var decoded: [69] u8
    let block = Swag.readCompressedDebugTable(&packed[0], packed.count)
    Swag.require(block.decodedSize == decoded.count)
    let success = block.decode(&packed[0], &decoded[0])
    Swag.require(success and Swag.validateDebugSection(&decoded[0], decoded.count))
    let startBytes: [4] u8 = [0, 0xFF, 0xFF, 0xFF]
    for byte, index in startBytes do
        Swag.require(decoded[16 + index] == byte)
    Swag.require(decoded[36] == 0x20)
    Swag.require(decoded[32] == 12 and decoded[52] == 8)

    var name      = ""
    let foundName = Swag.readDebugString(&decoded[0], decoded.count, 56, 65, &name)
    Swag.require(foundName and name == "two")

    // The final entry ends at the string blob. Stop reading continuation bytes at that boundary.
    packed[37] = 0x87
    let malformed = block.decode(&packed[0], &decoded[0])
    Swag.require(not malformed)

    writeDebugU32(packed, 12, payload.count + 1)
    let truncated = Swag.readCompressedDebugTable(&packed[0], packed.count)
    Swag.require(not truncated.decodedSize)
}
