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
        width:     u16            // Width of the logical screen.
        height:    u16            // Height of the logical screen.
        loopCount: u16            // Loop count from the animation extension, zero for endless.
        gce:       Gce            // Graphic control extension attached to the next frame.
        gct:       Palette        // Global color table of the stream.
        bgIndex:   u8             // Background color index of the logical screen.
        frame:     Array!{u8}     // Palette indices of the frame in encoded row order.

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
        if Memory.compare(sigver, ("GIF").buffer, 3) != 0
        {
            fail InvalidFormatError{"invalid signature"}
        }

        // Version
        .read(sigver, 3)
        if Memory.compare(sigver, ("89a").buffer, 3) != 0 and Memory.compare(sigver, ("87a").buffer, 3) != 0
        {
            fail InvalidFormatError{"invalid version"}
        }

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
        .seek(3_u64 * .gct.size)
    }

    // Decodes the next composited frame into `image`.
    //
    // The image is allocated or reconfigured as needed. Returns false after the GIF
    // trailer has been reached.
    mtd nextFrame(img: *Image)->bool fail
    {
        Swag.assert(.reader.isOpen())
        if .nextIndex >= .reader.info.frames.count
        {
            return false
        }

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
        if options.decodePixels and not opaqueStill and frame.pixelFormat == .RGB8
        {
            result.convertTo(.RGB8)
        }

        .reader    = #move reader
        .nextIndex = 1
        return result
    }
}

enum LzwMode
{
    PackedPhrases
    CopyPrefixes
    DenseLiterals
}

struct IndexedFrame
{
    data:       const [*] u8?
    palette:    Palette
    control:    Gce
    x:          u16
    y:          u16
    width:      u16
    height:     u16
    minKeySize: u8
    interlaced: bool
    lzwMode:    LzwMode
}

struct SetDecoder
{
    decoder: Decoder
    frames:  Array!{IndexedFrame}
    validatedThrough: s32 = -1
}

private func clearTransparentMargins(canvas: *Image, frame: const *IndexedFrame)
{
    let pixels = canvas.pixels.storage()
    let stride = cast(u64, canvas.rowStride)
    let below  = cast(u64, (canvas.height - frame.y - frame.height))
    let start  = pixels + below * stride
    Memory.clear(pixels, below * stride)
    Memory.clear(start + frame.height * stride, frame.y * stride)

    let left  = cast(u64, frame.x) * 4
    let end   = left + cast(u64, frame.width) * 4
    let right = stride - end
    if left or right
    {
        for y in frame.height
        {
            let row = start + y * stride
            Memory.clear(row, left)
            Memory.clear(row + end, right)
        }
    }
}

impl IImageDecoder for SetDecoder
{
    mtd impl format()->ImageFormat => {"GIF - Graphics Interchange Format", ".gif"}

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        let background = try .openCanvas(buffer, options)
        var first: IndexedFrame
        if not (try .decoder.getFrame(&first))
        {
            fail InvalidFormatError{"image container has no representative image"}
        }

        // Later frame descriptors still participate in container validation and limits.
        var count = 1_u64
        try options.checkFrameCount(count)
        var skipped: IndexedFrame
        while try .decoder.getFrame(&skipped)
        {
            count += 1
            try options.checkFrameCount(count)
        }

        let indexed = &first
        let format: PixelFormat = options.decodePixels and not indexed.control.transparency ? .RGB8 : .RGBA8
        var result: #returntype
        result.init(.decoder.width, .decoder.height, format)
        if not options.decodePixels
        {
            return result
        }

        try .decoder.decodeIndices(indexed)
        result.allocPixels()
        if indexed.width != .decoder.width or indexed.height != .decoder.height
        {
            // The first transparent frame starts on a transparent black canvas.
            if result.pixelFormat == .RGBA8
            {
                clearTransparentMargins(&result, indexed)
            }
            else
            {
                result.fill(background)
            }
        }

        // The decoded rectangle can be expanded directly into the final, bottom-up canvas.
        let bottom = result.height - indexed.y - indexed.height
        let target = result.pixels.storage() + cast(u64, bottom) * result.rowStride + cast(u64, indexed.x) * result.bytesPerPixel
        try .decoder.writePixels(indexed, target, result.rowStride, result.pixelFormat == .RGBA8, clearTransparent: true)
        return result
    }
}

impl IImageSetDecoder for SetDecoder
{
    mtd impl open(buffer: const [..] u8, options: DecodeOptions)->ImageSetInfo fail
    {
        .validatedThrough = -1
        var result: #returntype
        result.background   = try .openCanvas(buffer, options)
        result.canvasWidth  = .decoder.width
        result.canvasHeight = .decoder.height

        var indexed: IndexedFrame
        while try .decoder.getFrame(&indexed)
        {
            try options.checkFrameCount(.frames.count + 1)
            .frames.add(indexed)
            let control = indexed.control
            var disposal: ImageDisposal
            if control.disposal == 3
            {
                disposal = .Previous
            }
            else if control.disposal == 2
            {
                disposal = .Background
            }
            else
            {
                disposal = .Keep
            }

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
            if result.frames.count == 1 and control.transparency
            {
                result.background = {a: 0}
            }
        }

        result.loopCount = .decoder.hasLoopExtension ? (.decoder.loopCount ? cast(u32, .decoder.loopCount) + 1 : 0) : 1
        return result
    }

    mtd impl readFrame(index: u32, options: DecodeOptions)->Image fail
    {
        if index >= .frames.count
        {
            fail InvalidFormatError{"GIF frame index is out of range"}
        }

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

impl SetDecoder
{
    #[Swag.Inline]
    private mtd openCanvas(buffer: const [..] u8, options: DecodeOptions)->Color fail
    {
        .frames.clear()
        try .decoder.init(buffer)
        try options.checkImage(.decoder.width, .decoder.height, .RGBA8)
        if .decoder.bgIndex < .decoder.gct.size
        {
            let color = cast(const [*] u8, unwrap .decoder.gct.colors) + cast(u32, .decoder.bgIndex) * 3
            return {r: color[0], g: color[1], b: color[2], a: 255}
        }

        return {a: 0}
    }
}

#[Swag.Inline]
private func(HAS_ALPHA: bool) writeGatheredColors(target: [*] u8, table: const [*] s32, keys: Math.Simd.U32x4)
{
    let pixels = cast #bit(Math.Simd.U8x16, Math.Simd.gather(table, keys))
    #static if HAS_ALPHA
    {
        Math.Simd.store(target, pixels)
    }
    else
    {
        Image.storeLow12(target, Math.Simd.shuffle(pixels, PackedPixel.PaletteDropAlpha))
    }
}

impl Decoder
{
    mtd writePixels(indexed: const *IndexedFrame, pixels: [*] u8, stride: s32, hasAlpha, clearTransparent: bool) fail
    {
        let palette   = &indexed.palette
        let colors    = cast(const [*] u8, unwrap palette.colors)
        let alphaMask = hasAlpha ? 0xFF000000_u32 : 0
        var packed: [256] u32
        for paletteIndex in palette.size
        {
            let color = colors + paletteIndex * 3
            packed[paletteIndex] = cast(u32, color[0]) | (cast(u32, color[1]) << 8) |
                                   (cast(u32, color[2]) << 16) | alphaMask
        }

        if hasAlpha
        {
            packed[indexed.control.tindex] &= clearTransparent ? 0 : 0xFFFFFF
        }

        let width  = cast(s32, indexed.width)
        let height = cast(s32, indexed.height)
        if palette.size <= 16 and width >= 32 and cast(u64, width) * height >= 256
        {
            try .writeSmallPalettePixels(indexed, pixels, stride, hasAlpha, cast(const [*] u32, &packed[0]))
            return
        }

        // A full palette covers every possible index and needs no separate range scan.
        if palette.size == 256 and width >= 64
        {
            let table = cast(const [*] u32, &packed[0])
            if hasAlpha
            {
                .writeFullPalettePixels!{true}(indexed, pixels, stride, table)
            }
            else
            {
                .writeFullPalettePixels!{false}(indexed, pixels, stride, table)
            }

            return
        }

        if palette.size == 32 and width >= 64 and cast(u64, width) * height >= 256
        {
            let table = cast(const [*] u32, &packed[0])
            if hasAlpha
            {
                try .writeBankedPalettePixels!{true}(indexed, pixels, stride, table)
            }
            else
            {
                try .writeBankedPalettePixels!{false}(indexed, pixels, stride, table)
            }

            return
        }

        let indices         = .frame.storage()
        var combinedIndices = 0_u8
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
        if combinedIndices >= palette.size
        {
            fail InvalidFormatError{"GIF palette index is out of range"}
        }
    }

    #[Swag.NoInline]
    private mtd writeSmallPalettePixels(indexed: const *IndexedFrame, pixels: [*] u8, stride: s32, hasAlpha: bool, packed: const [*] u32) fail
    {
        let paletteSize = indexed.palette.size
        let width       = cast(s32, indexed.width)
        let height      = cast(s32, indexed.height)
        let indices     = .frame.storage()
        let step        = hasAlpha ? 4 : 3

        var tables          = PackedPixel.smallPaletteTables(packed, cast(u64, paletteSize))
        let tableData       = cast(const [*] Math.Simd.U8x16, &tables[0])
        var combinedIndices = 0_u8
        var combinedVectors = Math.Simd.splat(0_u8)
        for y in height
        {
            let source = indices + cast(u64, y) * width
            let row    = indexed.interlaced ? Decoder.interlacedLineIndex(height, y) : y
            let target = pixels + cast(u64, (height - row - 1)) * stride
            let start  = hasAlpha ? PackedPixel.writeSmallPaletteRow!{true}(source, target, width, tableData, &combinedVectors) :
                         PackedPixel.writeSmallPaletteRow!{false}(source, target, width, tableData, &combinedVectors)
            for x in start until width
            {
                let paletteIndex = source[x]
                let color        = packed[paletteIndex]
                let destination  = target + x * step
                if hasAlpha
                {
                    cast([*] u32, destination)[0] = color
                }
                else
                {
                    cast([*] u16, destination)[0] = cast(u16, (color & 0xFFFF))
                    destination[2] = cast(u8, (color >> 16))
                }

                combinedIndices |= paletteIndex
            }
        }

        let invalidBits = ~cast(u8, (paletteSize - 1))
        if combinedIndices >= paletteSize or Math.Simd.anyTrue((combinedVectors & invalidBits) != Math.Simd.splat(0_u8))
        {
            fail InvalidFormatError{"GIF palette index is out of range"}
        }
    }

    #[Swag.NoInline]
    private mtd(HAS_ALPHA: bool) writeFullPalettePixels(indexed: const *IndexedFrame, pixels: [*] u8, stride: s32, packed: const [*] u32)
    {
        const Step = HAS_ALPHA ? 4 : 3
        let width   = cast(s32, indexed.width)
        let height  = cast(s32, indexed.height)
        let indices = .frame.storage()
        let table   = cast(const [*] s32, packed)
        for y in height
        {
            let source = indices + cast(u64, y) * width
            let row    = indexed.interlaced ? Decoder.interlacedLineIndex(height, y) : y
            let target = pixels + cast(u64, (height - row - 1)) * stride
            var x      = 0
            while width - x >= 16
            {
                let keys        = Math.Simd.load(source + x)
                let lo          = Math.Simd.widenLow(keys)
                let hi          = Math.Simd.widenHigh(keys)
                let destination = target + x * Step
                writeGatheredColors!{HAS_ALPHA}(destination, table, Math.Simd.widenLow(lo))
                writeGatheredColors!{HAS_ALPHA}(destination + 4 * Step, table, Math.Simd.widenHigh(lo))
                writeGatheredColors!{HAS_ALPHA}(destination + 8 * Step, table, Math.Simd.widenLow(hi))
                writeGatheredColors!{HAS_ALPHA}(destination + 12 * Step, table, Math.Simd.widenHigh(hi))
                x += 16
            }

            for i in x until width
            {
                let color       = packed[source[i]]
                let destination = target + i * Step
                #static if HAS_ALPHA
                {
                    cast([*] u32, destination)[0] = color
                }
                else
                {
                    cast([*] u16, destination)[0] = cast(u16, (color & 0xFFFF))
                    destination[2] = cast(u8, (color >> 16))
                }
            }
        }
    }
}

impl SetDecoder
{
    // Expand directly on the animation canvas. GIF alpha either replaces or retains a pixel.
    mtd compositeFrame(index: u32, canvas: *Image) fail
    {
        Swag.assert(canvas.pixelFormat == .RGBA8)
        let indexed = &.frames[index]
        try .decoder.decodeIndices(indexed)
        let bottom = canvas.height - indexed.y - indexed.height
        let target = canvas.pixels.storage() + cast(u64, bottom) * canvas.rowStride + cast(u64, indexed.x) * 4
        try .decoder.compositeCanvasPixels(indexed, target, canvas.rowStride)
        .validatedThrough = Math.max(.validatedThrough, cast(s32, index))
    }

    // Only a validated frame that fills the canvas opaquely can skip earlier updates.
    // Previous disposal would still need the preceding canvas when reading its successor.
    mtd replayFrame(index, next: s32)->s32
    {
        var candidate = Math.min(index, .validatedThrough)
        while candidate > next
        {
            let frame = &.frames[candidate]
            if not frame.control.transparency and
               frame.control.disposal != 3 and
               frame.width == .decoder.width and
               frame.height == .decoder.height
            {
                return candidate
            }

            candidate -= 1
        }

        return next
    }
}

#[Swag.Inline]
private func compositeGatheredColors(target: [*] u32, table: const [*] s32, keys: Math.Simd.U32x4)
{
    let colors = cast #bit(Math.Simd.U32x4, Math.Simd.gather(table, keys))
    let opaque = (colors >> 24) == Math.Simd.splat(255_u32)
    if Math.Simd.allTrue(opaque)
    {
        Math.Simd.store(target, colors)
    }
    else
    {
        let previous = Math.Simd.load(target)
        let visible  = (previous >> 24) != Math.Simd.splat(0_u32)
        Math.Simd.store(target, (colors & opaque) | (previous & visible & ~opaque))
    }
}

impl Decoder
{
    mtd compositeCanvasPixels(indexed: const *IndexedFrame, pixels: [*] u8, stride: s32) fail
    {
        let palette = &indexed.palette
        let colors  = cast(const [*] u8, unwrap palette.colors)
        var packed: [256] u32
        for paletteIndex in palette.size
        {
            let color = colors + paletteIndex * 3
            packed[paletteIndex] = cast(u32, color[0]) | (cast(u32, color[1]) << 8) |
                                   (cast(u32, color[2]) << 16) | 0xFF000000
        }

        let width  = cast(s32, indexed.width)
        let height = cast(s32, indexed.height)
        let table  = cast(const [*] u32, &packed[0])
        if indexed.control.transparency
        {
            packed[indexed.control.tindex] = 0
        }
        else
        {
            if palette.size <= 16 and width >= 32 and cast(u64, width) * height >= 256
            {
                try .writeSmallPalettePixels(indexed, pixels, stride, true, table)
                return
            }

            if palette.size == 256 and width >= 64
            {
                .writeFullPalettePixels!{true}(indexed, pixels, stride, table)
                return
            }
        }

        if palette.size == 256
        {
            try .compositePalettePixels!{false}(indexed, pixels, stride, table)
        }
        else
        {
            try .compositePalettePixels!{true}(indexed, pixels, stride, table)
        }
    }

    #[Swag.NoInline]
    private mtd(CHECK_BOUNDS: bool) compositePalettePixels(indexed: const *IndexedFrame, pixels: [*] u8, stride: s32, packed: const [*] u32) fail
    {
        let width           = cast(s32, indexed.width)
        let height          = cast(s32, indexed.height)
        let indices         = .frame.storage()
        let table           = cast(const [*] s32, packed)
        var combinedVectors = Math.Simd.splat(0_u8)
        var combinedTail: u8
        for y in height
        {
            let source = indices + cast(u64, y) * width
            let row    = indexed.interlaced ? Decoder.interlacedLineIndex(height, y) : y
            let target = cast([*] u32, pixels + cast(u64, (height - row - 1)) * stride)
            var x      = 0
            while width >= 64 and width - x >= 16
            {
                let keys = Math.Simd.load(source + x)
                #static if CHECK_BOUNDS
                {
                    combinedVectors |= keys
                }

                let lo = Math.Simd.widenLow(keys)
                let hi = Math.Simd.widenHigh(keys)
                compositeGatheredColors(target + x, table, Math.Simd.widenLow(lo))
                compositeGatheredColors(target + x + 4, table, Math.Simd.widenHigh(lo))
                compositeGatheredColors(target + x + 8, table, Math.Simd.widenLow(hi))
                compositeGatheredColors(target + x + 12, table, Math.Simd.widenHigh(hi))
                x += 16
            }

            for i in x until width
            {
                let key = source[i]
                #static if CHECK_BOUNDS
                {
                    combinedTail |= key
                }

                let color = packed[key]
                if color >> 24
                {
                    target[i] = color
                }
                else if target[i] >> 24 == 0
                {
                    target[i] = 0
                }
            }
        }

        #static if CHECK_BOUNDS
        {
            let paletteSize = indexed.palette.size
            let invalidBits = ~cast(u8, paletteSize - 1)
            if combinedTail >= paletteSize or Math.Simd.anyTrue((combinedVectors & invalidBits) != Math.Simd.splat(0_u8))
            {
                fail InvalidFormatError{"GIF palette index is out of range"}
            }
        }
    }
}

impl Decoder
{
    #[Swag.NoInline]
    private mtd(HAS_ALPHA: bool) writeBankedPalettePixels(indexed: const *IndexedFrame, pixels: [*] u8, stride: s32, packed: const [*] u32) fail
    {
        const Step = HAS_ALPHA ? 4 : 3
        let width       = cast(s32, indexed.width)
        let height      = cast(s32, indexed.height)
        let indices     = .frame.storage()
        let low         = PackedPixel.smallPaletteTables(packed, 16)
        let high        = PackedPixel.smallPaletteTables(packed + 16, 16)
        let transparent = Math.Simd.splat(indexed.control.tindex)
        let allOpaque   = Math.Simd.splat(indexed.control.transparency ? 0_u8 : 255_u8)
        let highBit     = Math.Simd.splat(128_u8)
        let zero        = Math.Simd.splat(0_u8)
        var combined    = zero
        var combinedTail: u8
        for y in height
        {
            let source = indices + cast(u64, y) * width
            let row    = indexed.interlaced ? Decoder.interlacedLineIndex(height, y) : y
            let target = pixels + cast(u64, (height - row - 1)) * stride
            var x      = 0
            while width - x >= 16
            {
                let keys = Math.Simd.load(source + x)
                combined |= keys

                // The shuffle zeroes positions with bit 7 set and looks up the low nibble.
                let bankBits = cast #bit(Math.Simd.U16x8, keys) << 3
                let lo       = keys | (cast #bit(Math.Simd.U8x16, bankBits) & highBit)
                let hi       = lo ^ highBit
                let red      = Math.Simd.shuffle(low[0], lo) | Math.Simd.shuffle(high[0], hi)
                let green    = Math.Simd.shuffle(low[1], lo) | Math.Simd.shuffle(high[1], hi)
                let blue     = Math.Simd.shuffle(low[2], lo) | Math.Simd.shuffle(high[2], hi)
                let alpha    = HAS_ALPHA ? ((keys != transparent) | allOpaque) : zero
                let output   = target + x * Step
                PackedPixel.writeSmallPaletteHalf!{HAS_ALPHA}(output, Math.Simd.interleaveLow(red, green), Math.Simd.interleaveLow(blue, alpha))
                PackedPixel.writeSmallPaletteHalf!{HAS_ALPHA}(output + 8 * Step, Math.Simd.interleaveHigh(red, green), Math.Simd.interleaveHigh(blue, alpha))
                x += 16
            }

            for tail in x until width
            {
                let key    = source[tail]
                let color  = packed[key]
                let output = target + tail * Step
                #static if HAS_ALPHA
                {
                    cast([*] u32, output)[0] = color
                }
                else
                {
                    cast([*] u16, output)[0] = cast(u16, color & 0xFFFF)
                    output[2] = cast(u8, color >> 16)
                }

                combinedTail |= key
            }
        }

        if combinedTail >= 32 or Math.Simd.anyTrue((combined & Math.Simd.splat(0xE0_u8)) != zero)
        {
            fail InvalidFormatError{"GIF palette index is out of range"}
        }
    }
}
