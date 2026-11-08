#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Viewers

struct ZipFixtureEntry
{
    name:   String
    plain:  Array'u8
    packed: Array'u8
    method: u16
    crc32:  u32
    local:  u64
}

func zipFixtureU16(bytes: *Array'u8, value: u16)
{
    bytes.add(cast #bit (u8, value))
    bytes.add(cast #bit (u8, (value >> 8)))
}

func zipFixtureU32(bytes: *Array'u8, value: u32)
{
    zipFixtureU16(bytes, cast #bit (u16, value))
    zipFixtureU16(bytes, cast #bit (u16, (value >> 16)))
}

func addZipFixtureEntry(bytes: *Array'u8, entry: *ZipFixtureEntry)
{
    entry.crc32 = Hash.Crc32.compute(entry.plain.toSlice())
    entry.local = bytes.count
    zipFixtureU32(bytes, 0x04034B50)
    zipFixtureU16(bytes, 20)
    zipFixtureU16(bytes, 1 << 11)
    zipFixtureU16(bytes, entry.method)
    zipFixtureU16(bytes, 0)
    zipFixtureU16(bytes, 0)
    zipFixtureU32(bytes, entry.crc32)
    zipFixtureU32(bytes, cast(u32, entry.packed.count))
    zipFixtureU32(bytes, cast(u32, entry.plain.count))
    zipFixtureU16(bytes, cast(u16, entry.name.length))
    zipFixtureU16(bytes, 0)
    bytes.add(entry.name.toSlice())
    bytes.add(entry.packed.toSlice())
}

// Builds a stored or Deflate ZIP from the authored entries, including its central directory.
func buildZipEntries(entries: [..] ZipFixtureEntry)->Array'u8
{
    var result: #returntype
    for &entry in entries do
        addZipFixtureEntry(&result, entry)

    let directoryAt = result.count
    for entry in entries
    {
        zipFixtureU32(&result, 0x02014B50)
        zipFixtureU16(&result, 20)
        zipFixtureU16(&result, 20)
        zipFixtureU16(&result, 1 << 11)
        zipFixtureU16(&result, entry.method)
        zipFixtureU16(&result, 0)
        zipFixtureU16(&result, 0)
        zipFixtureU32(&result, entry.crc32)
        zipFixtureU32(&result, cast(u32, entry.packed.count))
        zipFixtureU32(&result, cast(u32, entry.plain.count))
        zipFixtureU16(&result, cast(u16, entry.name.length))
        zipFixtureU16(&result, 0)
        zipFixtureU16(&result, 0)
        zipFixtureU16(&result, 0)
        zipFixtureU16(&result, 0)
        zipFixtureU32(&result, 0)
        zipFixtureU32(&result, cast(u32, entry.local))
        result.add(entry.name.toSlice())
    }

    let directorySize = result.count - directoryAt
    zipFixtureU32(&result, 0x06054B50)
    zipFixtureU16(&result, 0)
    zipFixtureU16(&result, 0)
    zipFixtureU16(&result, cast(u16, entries.count))
    zipFixtureU16(&result, cast(u16, entries.count))
    zipFixtureU32(&result, cast(u32, directorySize))
    zipFixtureU32(&result, cast(u32, directoryAt))
    zipFixtureU16(&result, 0)
    return result
}
