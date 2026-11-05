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
