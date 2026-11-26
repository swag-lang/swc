//! Format: Graphics Interchange Format (GIF87a/GIF89a) decoder component.
//! Supported: Global/local palettes, transparency, interlacing, disposal, timing, loops, and sequential animation frames.
//! Not supported: Unknown extension labels and malformed or truncated sub-block streams.
//! Role: This file owns decoder state and top-level GIF parsing.
//
// @LICENCE: LicenseRef-Public-Domain
// @ORIGIN: gifdec, https://github.com/lecram/gifdec
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#gifdec

#global namespace Gif

using Swag, Core, Core.Errors

private
{
    struct Entry
    {
        length: u16
        prefix: u16
        suffix: u8
    }

    struct Table
    {
        bulk:     s32
        nentries: s32
        entries:  Array'Entry
    }

    struct Palette
    {
        size:   s32
        colors: [0x100 * 3] u8
    }

    struct Gce
    {
        delay:        u16
        tindex:       u8
        disposal:     u8
        input:        s32
        transparency: s32
    }
}

impl Entry
{
    mtd const opCompare(other: Entry)->s32
    {
        let lenCmp = .length <=> other.length
        if lenCmp do
            return lenCmp

        let prefixCmp = .prefix <=> other.prefix
        if prefixCmp do
            return prefixCmp

        return .suffix <=> other.suffix
    }
}

// Decodes GIF images and retains animation state for sequential frames.
//
// Treat the structure as opaque. Use it through [[Pixel.IImageDecoder]] or the
// GIF animation operations exposed by this module.
#[Swag.Opaque]
public struct Decoder
{
    // Decoding state: the logical screen, the frame being assembled, and the input cursor.
    // Drive the decoder through its methods; every field below is one step of that work.

    private
    {
        width:      u16           // Width of the logical screen.
        height:     u16           // Height of the logical screen.
        loopCount:  u16           // Loop count from the animation extension, zero for endless.
        gce:        Gce           // Graphic control extension of the current frame.
        palette:    *Palette?     // Palette the current frame resolves against.
        lct:        Palette       // Local color table of the current frame.
        gct:        Palette       // Global color table of the stream.
        fx:         u16           // Left edge of the current frame in the logical screen.
        fy:         u16           // Top edge of the current frame in the logical screen.
        fw:         u16           // Width of the current frame.
        fh:         u16           // Height of the current frame.
        bgIndex:    u8            // Background color index of the logical screen.
        interlaced: bool          // Whether the current frame stores rows in four passes.
        frame:      Array'u8      // Palette indices of the frame in encoded row order.
        table:      Table         // LZW dictionary of the current frame.

        streamStart:         const [*] u8?     // Start of the input, kept for looping.
        stream:              const [*] u8?     // Current read position in the input.
        streamLen:           u64     // Bytes remaining from 'stream'.
        descriptorOffset:    u64
        descriptorRemaining: u64
        hasLoopExtension:    bool
        reader:              ImageReader
        nextIndex:           u32
    }
}

impl Decoder
{
    mtd safeStream()->const [*] u8      => cast(const [*] u8, unwrap .stream)
    mtd safeStreamStart()->const [*] u8 => cast(const [*] u8, unwrap .streamStart)
    mtd safePalette()->*Palette         => cast(*Palette, unwrap .palette)
}

public impl Decoder
{
    // Opens an animated GIF for sequential frame decoding.
    //
    // The decoder owns a copy of `buffer`; the caller may release its input after this call.
    mtd open(buffer: const [..] u8) fail
    {
        var reader = try ImageReader.decode("image.gif", buffer)
        Swag.drop(me, 1)
        Swag.init(me, 1)
        .reader = #move reader
    }

    #[Swag.Propagate]
    internal mtd init(buffer: const [..] u8) fail
    {
        Swag.drop(me, 1)
        Swag.init(me, 1)

        .streamStart, .stream = buffer.buffer
        .streamLen = buffer.count

        // Header
        var sigver: [3] u8
        .read(sigver, 3)
        if Memory.compare(sigver, ("GIF").buffer, 3) != 0 do
            fail InvalidFormatError{"invalid signature"}

        // Version
        .read(sigver, 3)
        if Memory.compare(sigver, ("89a").buffer, 3) != 0 and Memory.compare(sigver, ("87a").buffer, 3) != 0 do
            fail InvalidFormatError{"invalid version"}

        // Width x Height
        .width  = .readU16()
        .height = .readU16()

        // FDSZ
        var fdsz: u8
        .read(&fdsz, 1)

        // Ignore sort flag
        // GCT Size
        .gct.size = fdsz & 0x80 ? 1 << ((fdsz & 0x07) + 1) : 0

        // Background color index
        .bgIndex = .readU8()

        // Aspect ratio
        discard .readU8()

        .read(.gct.colors, 3'u64 * .gct.size)
        .palette = &.gct
    }

    // Decodes the next composited frame into `image`.
    //
    // The image is allocated or reconfigured as needed. Returns false after the GIF
    // trailer has been reached.
    mtd nextFrame(img: *Image)->bool fail
    {
        Swag.assert(.reader.isOpen())
        if .nextIndex >= .reader.info.frames.count do
            return false
        img[]      = try .reader.read(.nextIndex)
        .nextIndex += 1
        return true
    }

    // Returns the number of frames indexed when the GIF was opened.
    mtd frameCount()->s32 fail
    {
        Swag.assert(.reader.isOpen())
        return cast(s32, .reader.info.frames.count)
    }

    // Rewinds frame iteration to the first frame.
    mtd rewind()
    {
        Swag.assert(.reader.isOpen())
        .nextIndex = 0
    }
}

public impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => {"GIF - Graphics Interchange Format", ".gif"}

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        var reader = try ImageReader.decode("image.gif", buffer, options)
        let frame  = reader.info.frames[0]

        // An opaque still covering its canvas can retain the decoded RGB pixels directly.
        let opaqueStill = options.decodePixels and
                          reader.info.frames.count == 1 and
                          frame.pixelFormat == .RGB8 and
                          frame.width == reader.info.canvasWidth and
                          frame.height == reader.info.canvasHeight
        var result: #returntype = try reader.readFrame(0, composeAnimation: not opaqueStill)
        if options.decodePixels and not opaqueStill and frame.pixelFormat == .RGB8 do
            result.convertTo(.RGB8)
        .reader    = #move reader
        .nextIndex = 1
        return result
    }
}

struct IndexedFrame
{
    offset:    u64
    remaining: u64
    control:   Gce
}

struct SetDecoder
{
    decoder: Decoder
    frames:  Array'IndexedFrame
}

impl IImageDecoder for SetDecoder
{
    mtd impl format()->ImageFormat => {"GIF - Graphics Interchange Format", ".gif"}

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        var decoder: Decoder
        let single:  IImageDecoder = &decoder
        return try single.decode(buffer, options)
    }
}

impl IImageSetDecoder for SetDecoder
{
    mtd impl open(buffer: const [..] u8, options: DecodeOptions)->ImageSetInfo fail
    {
        .frames.clear()
        try .decoder.init(buffer)
        try options.checkImage(.decoder.width, .decoder.height, .RGBA8)
        var result: #returntype
        result.canvasWidth  = .decoder.width
        result.canvasHeight = .decoder.height
        if .decoder.bgIndex < .decoder.gct.size
        {
            let color = cast(const [*] u8, &.decoder.gct.colors[cast(u32, .decoder.bgIndex) * 3])
            result.background = {r: color[0], g: color[1], b: color[2], a: 255}
        }

        while try .decoder.getFrame(false)
        {
            try options.checkFrameCount(.frames.count + 1)
            .frames.add(IndexedFrame{.decoder.descriptorOffset, .decoder.descriptorRemaining, .decoder.gce})
            let control = .decoder.gce
            var disposal: ImageDisposal
            if control.disposal == 3 do
                disposal = .Previous
            elif control.disposal == 2 do
                disposal = .Background
            else do
                disposal = .Keep

            let frame: ImageFrameInfo = ImageFrameInfo{
                kind: .Animation,
                width: .decoder.fw,
                height: .decoder.fh,
                x: .decoder.fx,
                y: .decoder.fy,
                pixelFormat: control.transparency ? .RGBA8 : .RGB8,
                durationSeconds: cast(f64, control.delay) / 100,
                disposal: disposal,
                blend: .Over}
            result.frames.add(frame)
            if result.frames.count == 1 and control.transparency do
                result.background = {a: 0}
        }

        result.loopCount = .decoder.hasLoopExtension ? (.decoder.loopCount ? cast(u32, .decoder.loopCount) + 1 : 0) : 1
        return result
    }

    mtd impl readFrame(index: u32, options: DecodeOptions)->Image fail
    {
        if index >= .frames.count do
            fail InvalidFormatError{"GIF frame index is out of range"}
        .decoder.stream    = .decoder.streamStart + .frames[index].offset
        .decoder.streamLen = .frames[index].remaining
        .decoder.gce       = .frames[index].control
        try .decoder.readImage(options.decodePixels)
        var result: #returntype
        result.init(.decoder.fw, .decoder.fh, .decoder.gce.transparency ? .RGBA8 : .RGB8)
        if not options.decodePixels do
            return result
        result.allocPixels()
        let palette   = unwrap .decoder.palette
        let hasAlpha  = result.pixelFormat == .RGBA8
        let alphaMask = hasAlpha ? 0xFF000000'u32 : 0
        var packed: [256] u32
        for paletteIndex in palette.size
        {
            let color = cast(const [*] u8, &palette.colors[paletteIndex * 3])
            packed[paletteIndex] = cast(u32, color[0]) | (cast(u32, color[1]) << 8) |
                                   (cast(u32, color[2]) << 16) | alphaMask
        }

        if hasAlpha do
            packed[.decoder.gce.tindex] &= 0xFFFFFF

        let indices         = .decoder.frame.storage()
        let pixels          = result.pixels.storage()
        var combinedIndices = 0'u8
        for y in result.height
        {
            let source = indices + cast(u64, y) * result.width
            let row    = .decoder.interlaced ? Decoder.interlacedLineIndex(result.height, y) : y
            let target = pixels + cast(u64, (result.height - row - 1)) * result.rowStride
            if hasAlpha
            {
                let words = cast([*] u32, target)
                for x in result.width
                {
                    let paletteIndex = source[x]
                    words[x]        = packed[paletteIndex]
                    combinedIndices |= paletteIndex
                }
            }
            else
            {
                // Each wide store overlaps the next pixel. Write exactly three bytes at the row end.
                let lastX = result.width - 1
                for x in lastX
                {
                    let paletteIndex = source[x]
                    cast([*] u32, (target + x * 3))[0] = packed[paletteIndex]
                    combinedIndices |= paletteIndex
                }

                let paletteIndex = source[lastX]
                let color        = packed[paletteIndex]
                let last         = target + lastX * 3
                cast([*] u16, last)[0] = cast(u16, (color & 0xFFFF))
                last[2]                = cast(u8, (color >> 16))
                combinedIndices        |= paletteIndex
            }
        }

        // GIF palette sizes are powers of two, so any index with a high bit is out of range.
        if combinedIndices >= palette.size do
            fail InvalidFormatError{"GIF palette index is out of range"}

        return result
    }
}
