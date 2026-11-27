//! Format: Annex B start-code-delimited byte streams.
//! Supported: Three-byte start codes, optional zero bytes, and file or memory sources.
//! Not supported: Interpretation of codec-specific network abstraction layer headers.
//! Role: This file locates byte ranges without retaining coded payloads.
//
#global internal

using Core, Core.Errors

const MaxAnnexAccessUnit = 64 * 1024 * 1024_u64
const MaxAnnexFrames     = 1_048_576_u64

struct AnnexBNal
{
    start:   u64     // First zero of the run before the start code's final one.
    payload: u64     // First byte after the start code.
    size:    u64     // Payload bytes before any trailing zeros.
}

struct AnnexBScanner
{
    start:   u64
    payload: u64
    hasNext: bool
}

impl AnnexBScanner
{
    mtd open(source: *ByteSource) fail
    {
        try source.seek(0)
        let boundary = try .findBoundary(source)
        if not boundary.hasCode or boundary.end != 0
        {
            fail InvalidFormatError{"Annex B stream has no leading start code"}
        }

        .start   = 0
        .payload = source.position()
        .hasNext = true
    }

    // Reads one range while allowing another caller to reposition the source between units.
    mtd next(source: *ByteSource, unit: *AnnexBNal)->bool fail
    {
        if not .hasNext
        {
            return false
        }

        try source.seek(.payload)
        let boundary = try .findBoundary(source)
        if boundary.end <= .payload
        {
            fail InvalidFormatError{"Annex B stream has an empty network abstraction layer unit"}
        }

        unit[]   = {.start, .payload, boundary.end - .payload}
        .start   = boundary.end
        .payload = source.position()
        .hasNext = boundary.hasCode
        return true
    }

    // Finds the next start code across read windows. The position returned excludes the
    // preceding zero run even when some of it was in the previous window.
    private mtd findBoundary(source: *ByteSource)->{ end: u64, hasCode: bool } fail
    {
        var precedingZeros = 0_u64
        while not source.isAtEnd()
        {
            let first  = source.position()
            let bytes  = try source.peek(1)
            var offset = 0_u64
            while offset < bytes.count
            {
                let relative = Slice.findLinear(bytes[offset until bytes.count], 1_u8)
                if relative == Swag.U64.Max
                {
                    break
                }

                let index = offset + relative
                var start = index
                while start and bytes[start - 1] == 0
                {
                    start -= 1
                }

                let zeros = index - start + (start == 0 ? precedingZeros : 0)
                if zeros >= 2
                {
                    try source.skip(index + 1)
                    return {first + index - zeros, true}
                }

                offset = index + 1
            }

            var end = bytes.count
            while end and bytes[end - 1] == 0
            {
                end -= 1
            }

            precedingZeros = bytes.count - end + (end == 0 ? precedingZeros : 0)
            try source.skip(bytes.count)
        }

        return {source.position() - precedingZeros, false}
    }
}

// Copies a stored Annex B access unit into the same packet representation as the containers.
func packAnnexAccessUnit(bytes: const [..] u8, packet: *Array!{u8}) fail
{
    var source = ByteSource.openMemory(bytes)
    var scanner: AnnexBScanner
    try scanner.open(&source)

    packet.clear()
    var unit: AnnexBNal
    while try scanner.next(&source, &unit)
    {
        appendAnnexNal(packet, bytes[unit.payload until unit.payload + unit.size])
    }
}

// Appends one unit to the same four-byte length framing used by container samples.
func appendAnnexNal(packet: *Array!{u8}, bytes: const [..] u8)
{
    let size = bytes.count
    packet.add(cast(u8, size >> 24))
    packet.add(cast(u8, ((size >> 16) & 255)))
    packet.add(cast(u8, ((size >> 8) & 255)))
    packet.add(cast(u8, (size & 255)))
    packet.add(bytes)
}
