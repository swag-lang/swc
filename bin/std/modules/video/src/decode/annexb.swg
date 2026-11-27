//! Format: Annex B start-code-delimited byte streams.
//! Supported: Three-byte start codes, optional zero bytes, and file or memory sources.
//! Not supported: Interpretation of codec-specific network abstraction layer headers.
//! Role: This file locates byte ranges without retaining coded payloads.
//
#global internal

using Core, Core.Errors

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
