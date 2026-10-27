//! Format: RealVideo 4 packet framing.
//! Role: Validate the slice directory and expose each slice without copying its payload.
//
#global namespace RealVideo
#global internal

using Core, Core.Errors

// A packet borrows its input. Slice offsets are relative to the payload after the directory.
struct Packet
{
    bytes:   const [..] u8
    offsets: Array'u32
    payload: u64
}

impl Packet
{
    // Reads one little- or big-endian directory word.
    private func word(bytes: const [..] u8, offset: u64, little: bool)->u32
    {
        var value = 0'u32
        for index in 4'u64
        {
            let position = little ? 3 - index : index
            value = (value << 8) | cast(u32, bytes[offset + position])
        }

        return value
    }

    // Validates the complete directory before any slice is exposed.
    func open(bytes: const [..] u8)->Packet fail
    {
        if not bytes.count do
            fail InvalidFormatError{"RealVideo packet has no slice directory"}
        let count   = cast(u64, bytes[0]) + 1
        let payload = 1 + count * 8
        if payload >= bytes.count do
            fail InvalidFormatError{"RealVideo slice directory is truncated"}

        var result = Packet{bytes, {}, payload}
        for index in count
        {
            let entry  = 1 + index * 8
            let little = word(bytes, entry, true) == 1
            if not little and word(bytes, entry, false) != 1 do
                fail InvalidFormatError{"RealVideo slice directory has an invalid marker"}
            let offset = word(bytes, entry + 4, little)
            if cast(u64, offset) >= bytes.count - payload or
               (index == 0 and offset != 0) or
               (index > 0 and offset <= result.offsets[index - 1]) do
                fail InvalidFormatError{"RealVideo slice offset is invalid"}
            result.offsets.add(offset)
        }

        return result
    }

    mtd const slice(index: u64)->const [..] u8
    {
        Swag.assert(index < .offsets.count)
        let start = .payload + cast(u64, .offsets[index])
        let end   = index + 1 < .offsets.count ? .payload + cast(u64, .offsets[index + 1]) : .bytes.count
        return .bytes[start until end]
    }
}
