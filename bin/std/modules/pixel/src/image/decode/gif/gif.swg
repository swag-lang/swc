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
    struct Palette
    {
        size:   s32
        colors: const [*] u8?
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
        width:     u16          // Width of the logical screen.
        height:    u16          // Height of the logical screen.
        loopCount: u16          // Loop count from the animation extension, zero for endless.
        gce:       Gce          // Graphic control extension attached to the next frame.
        gct:       Palette      // Global color table of the stream.
        bgIndex:   u8           // Background color index of the logical screen.
        frame:     Array'u8     // Palette indices of the frame in encoded row order.

        stream:           const [*] u8?     // Current read position in the input.
        streamLen:        u64     // Bytes remaining from 'stream'.
        hasLoopExtension: bool
        reader:           ImageReader
        nextIndex:        u32
    }
}

impl Decoder
{
    mtd safeStream()->const [*] u8 => cast(const [*] u8, unwrap .stream)
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

        .stream    = buffer.buffer
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

        .gct.colors = .stream
        .seek(3'u64 * .gct.size)
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
    data:            const [*] u8?
    palette:         Palette
    control:         Gce
    x:               u16
    y:               u16
    width:           u16
    height:          u16
    minKeySize:      u8
    interlaced:      bool
    copyLzwPrefixes: bool
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
        let multiple: IImageSetDecoder = me
        let info = try multiple.open(buffer, options)
        if info.frames.isEmpty() do
            fail InvalidFormatError{"image container has no representative image"}

        let descriptor = &info.frames[0]
        var result: #returntype
        result.init(info.canvasWidth, info.canvasHeight, options.decodePixels ? descriptor.pixelFormat : .RGBA8)
        if not options.decodePixels do
            return result

        let indexed = &.frames[0]
        try .decoder.decodeIndices(indexed)
        result.allocPixels()
        if descriptor.width != info.canvasWidth or descriptor.height != info.canvasHeight do
            result.fill(info.background)

        // The decoded rectangle can be expanded directly into the final, bottom-up canvas.
        let bottom = result.height - descriptor.y - descriptor.height
        let target = result.pixels.storage() + cast(u64, bottom) * result.rowStride + cast(u64, descriptor.x) * result.bytesPerPixel
        try .decoder.writePixels(indexed, target, result.rowStride, result.pixelFormat == .RGBA8, clearTransparent: true)
        return result
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
            let color = cast(const [*] u8, unwrap .decoder.gct.colors) + cast(u32, .decoder.bgIndex) * 3
            result.background = {r: color[0], g: color[1], b: color[2], a: 255}
        }

        var indexed: IndexedFrame
        while try .decoder.getFrame(&indexed)
        {
            try options.checkFrameCount(.frames.count + 1)
            .frames.add(indexed)
            let control = indexed.control
            var disposal: ImageDisposal
            if control.disposal == 3 do
                disposal = .Previous
            elif control.disposal == 2 do
                disposal = .Background
            else do
                disposal = .Keep

            let frame: ImageFrameInfo = ImageFrameInfo{
                kind: .Animation,
                width: indexed.width,
                height: indexed.height,
                x: indexed.x,
                y: indexed.y,
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

        let indexed = &.frames[index]
        var result: #returntype
        result.init(indexed.width, indexed.height, indexed.control.transparency ? .RGBA8 : .RGB8)
        if options.decodePixels
        {
            try .decoder.decodeIndices(indexed)
            result.allocPixels()
            try .decoder.writePixels(indexed, result.pixels.storage(), result.rowStride, result.pixelFormat == .RGBA8, clearTransparent: false)
        }

        return result
    }
}

impl Decoder
{
    mtd writePixels(indexed: const *IndexedFrame, pixels: [*] u8, stride: s32, hasAlpha, clearTransparent: bool) fail
    {
        let palette   = &indexed.palette
        let colors    = cast(const [*] u8, unwrap palette.colors)
        let alphaMask = hasAlpha ? 0xFF000000'u32 : 0
        var packed: [256] u32
        for paletteIndex in palette.size
        {
            let color = colors + paletteIndex * 3
            packed[paletteIndex] = cast(u32, color[0]) | (cast(u32, color[1]) << 8) |
                                   (cast(u32, color[2]) << 16) | alphaMask
        }

        if hasAlpha do
            packed[indexed.control.tindex] &= clearTransparent ? 0 : 0xFFFFFF

        let width           = cast(s32, indexed.width)
        let height          = cast(s32, indexed.height)
        let indices         = .frame.storage()
        var combinedIndices = 0'u8
        for y in height
        {
            let source = indices + cast(u64, y) * width
            let row    = indexed.interlaced ? Decoder.interlacedLineIndex(height, y) : y
            let target = pixels + cast(u64, (height - row - 1)) * stride
            if hasAlpha
            {
                let words = cast([*] u32, target)
                for x in width
                {
                    let paletteIndex = source[x]
                    words[x]        = packed[paletteIndex]
                    combinedIndices |= paletteIndex
                }
            }
            else
            {
                // Each wide store overlaps the next pixel. Write exactly three bytes at the row end.
                let lastX = width - 1
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
    }
}
