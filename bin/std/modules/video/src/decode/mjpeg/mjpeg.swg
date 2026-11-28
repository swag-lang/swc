//! Format: Raw Motion JPEG decoder.
//! Supported: Concatenated, self-contained 8-bit sequential or progressive Huffman JPEG pictures of constant dimensions, at 25 frames per second.
//! Not supported: Multipart framing, shared JPEG tables, changing dimensions, audio, and stream timestamps.
//! Role: This file indexes JPEG boundaries and hands each picture to the Pixel JPEG decoder.
//
#global namespace Mjpeg
#global internal

using Core, Core.Errors, Pixel

private const StartImage = 0xD8_u8
private const EndImage   = 0xD9_u8
private const StartScan  = 0xDA_u8

// Keep the largest frame index to eight MiB, as each entry holds only an end offset.
private const MaxFrames = 1_048_576_u64

private struct Geometry
{
    width, height: s32
    components:    u8
}

struct Decoder
{
    private
    {
        ends:      Array!{u64}     // The next frame begins where the preceding one ends.
        geometry:  Geometry
        nextFrame: u64
    }
}

impl IDecoder for Decoder
{
    mtd impl format()->StreamFormat => {"Motion JPEG", ".mjpeg;.mjpg"}

    mtd impl open(source: *ByteSource)->StreamInfo fail
    {
        if source.isAtEnd()
        {
            fail InvalidFormatError{"Motion JPEG stream has no pictures"}
        }

        let limits: DecodeOptions
        while not source.isAtEnd()
        {
            if .ends.count == MaxFrames
            {
                fail UnsupportedFormatError{"Motion JPEG stream exceeds 1048576 pictures"}
            }

            let extent   = Math.min(source.remaining(), limits.maxInputBytes)
            let boundary = source.position() + extent
            let geometry = try scanFrame(source, boundary)
            if .ends.isEmpty()
            {
                let pixels = cast(u64, geometry.width) * cast(u64, geometry.height)
                if pixels > limits.maxPixels or pixels > limits.maxDecodedBytes / 3
                {
                    fail UnsupportedFormatError{"Motion JPEG picture exceeds the decoded image limits"}
                }

                .geometry = geometry
            }
            else if geometry.width != .geometry.width or geometry.height != .geometry.height
            {
                fail UnsupportedFormatError{"Motion JPEG stream changes picture dimensions"}
            }

            .ends.add(source.position())
        }

        try source.seek(0)
        return {
            width: .geometry.width,
            height: .geometry.height,
            codecName: "Motion JPEG",
            frameRate: try FrameRate.create(25, 1),
            frameCount: .ends.count}
    }

    mtd impl seekFrame(source: *ByteSource, index: u64) fail
    {
        if index >= .ends.count
        {
            fail BadParameterError{"Motion JPEG frame index exceeds the stream frame count"}
        }

        if index != .nextFrame
        {
            try source.seek(index ? .ends[index - 1] : 0)
            .nextFrame = index
        }
    }

    mtd impl decodeFrame(source: *ByteSource, target: *Image) fail
    {
        if .nextFrame >= .ends.count
        {
            fail InvalidFormatError{"Motion JPEG stream has no more pictures"}
        }

        let count = .ends[.nextFrame] - source.position()
        let bytes = try source.peek(count)
        try Jpg.decodeRgbInto(target, bytes[until count], .geometry.width, .geometry.height)
        try source.skip(count)
        .nextFrame += 1
    }

    mtd impl syncFrameAt(index: u64)->u64 => Math.min(index, .ends.count)
}

// Walks the markers without retaining entropy data. Segment lengths keep embedded bytes in
// headers from being mistaken for frame boundaries.
private func scanFrame(source: *ByteSource, boundary: u64)->Geometry fail
{
    if (try nextMarker(source, boundary, false)) != StartImage
    {
        fail InvalidFormatError{"Motion JPEG picture needs a start-of-image marker"}
    }

    var geometry: Geometry
    var seenScan, entropy: bool
    while source.position() < boundary
    {
        let marker = try nextMarker(source, boundary, entropy)
        if marker == EndImage
        {
            if not seenScan
            {
                fail InvalidFormatError{"Motion JPEG picture ends before its first scan"}
            }

            return geometry
        }

        if marker == StartImage
        {
            fail InvalidFormatError{"Motion JPEG picture is missing its end-of-image marker"}
        }

        if boundary - source.position() < 2
        {
            fail InvalidFormatError{"Motion JPEG marker is missing its segment length"}
        }

        let length = cast(u64, try source.readBigEndian!{u16}())
        if length < 2 or length - 2 > boundary - source.position()
        {
            fail InvalidFormatError{"Motion JPEG marker segment runs outside its picture boundary"}
        }

        entropy = false
        switch marker
        {
        case 0xC0, 0xC1, 0xC2:
            if geometry.width or length < 8
            {
                fail InvalidFormatError{"Motion JPEG picture needs one complete frame header"}
            }

            let fields = try source.peek(6)
            if fields[0] != 8
            {
                fail UnsupportedFormatError{"Motion JPEG supports eight-bit pictures"}
            }

            geometry.height     = (cast(s32, fields[1]) << 8) | fields[2]
            geometry.width      = (cast(s32, fields[3]) << 8) | fields[4]
            geometry.components = fields[5]
            if not geometry.width or
               not geometry.height or
               not geometry.components or
               length != 8 + 3 * cast(u64, geometry.components)
            {
                fail InvalidFormatError{"Motion JPEG frame header has incomplete dimensions or components"}
            }

            if geometry.components != 1 and geometry.components != 3 and geometry.components != 4
            {
                fail UnsupportedFormatError{"Motion JPEG supports one, three, or four JPEG components"}
            }

        case StartScan:
            if not geometry.width or length < 8
            {
                fail InvalidFormatError{"Motion JPEG scan needs a frame header and scan components"}
            }

            let header = try source.peek(1)
            let count  = header[0]
            if not count or count > geometry.components or length != 6 + 2 * cast(u64, count)
            {
                fail InvalidFormatError{"Motion JPEG scan header has incomplete components"}
            }

            seenScan = true
            entropy  = true

        case 0xC4, 0xDB, 0xDD, 0xFE:

            // Huffman and quantization tables, restart interval, or comment.
            break

        default:
            if marker < 0xE0 or marker > 0xEF
            {
                fail UnsupportedFormatError{"Motion JPEG picture contains an unsupported JPEG marker"}
            }
        }

        try source.skip(length - 2)
    }

    fail InvalidFormatError{"Motion JPEG picture is missing its end-of-image marker"}
}

// Finds the next structural marker. Stuffed bytes and restart markers belong to entropy data,
// and a marker prefix can run from the last byte of one source window into the next.
private func nextMarker(source: *ByteSource, boundary: u64, entropy: bool)->u8 fail
{
    var prefix = false
    while source.position() < boundary
    {
        let next  = try source.peek(1)
        let bytes = next[until Math.min(next.count, boundary - source.position())]
        var index = 0_u64
        while index < bytes.count
        {
            if not prefix
            {
                if entropy
                {
                    let offset = Slice.findLinear(bytes[index to], 0xFF_u8)
                    if offset == Swag.U64.Max
                    {
                        break
                    }

                    index += offset
                }
                else if bytes[index] != 0xFF
                {
                    fail InvalidFormatError{"Motion JPEG picture needs a JPEG marker prefix"}
                }

                index  += 1
                prefix = true
                continue
            }

            let marker = bytes[index]
            index += 1
            if marker == 0xFF
            {
                continue
            }

            if not marker or (marker >= 0xD0 and marker <= 0xD7)
            {
                if not entropy
                {
                    fail InvalidFormatError{"Motion JPEG stuffed bytes and restart markers need a scan"}
                }

                prefix = false
                continue
            }

            try source.skip(index)
            return marker
        }

        try source.skip(bytes.count)
    }

    fail InvalidFormatError{"Motion JPEG picture is missing its end-of-image marker"}
}
