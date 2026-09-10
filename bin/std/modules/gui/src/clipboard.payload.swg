#global namespace Clipboard

using Core

// A typed clipboard envelope borrows its bytes until they are copied or serialized.
struct TypedPayload
{
    crc:  u32
    data: const [..] u8?
}

impl TypedPayload
{
    mtd encode()->Array'u8
    {
        var result: retval
        var stream = ByteStream.openWrite(&result)
        stream.writeLittleEndian(.crc)
        stream.writeLittleEndian(.data.count)
        if .data do
            stream.writeBytes(.data)
        return result
    }

    func decode(bytes: const [..] u8)->TypedPayload fail
    {
        var stream = ByteStream.openRead(bytes)
        var result: retval
        result.crc = try stream.readLittleEndian'u32()
        let count     = try stream.readLittleEndian'u64()
        let remaining = stream.remainingBytes()
        if count > remaining.count do
            fail Errors.InvalidFormatError{"clipboard payload is truncated"}
        result.data = remaining[0 until count]
        return result
    }

    mtd const matches(type: typeinfo?)->bool => not type or .crc == type.crc
}
