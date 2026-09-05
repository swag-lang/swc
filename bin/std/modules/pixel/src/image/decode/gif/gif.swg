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
        fd:         s32           // Frame delay of the frame being decoded, in hundredths of a second.
        width:      u16           // Width of the logical screen.
        height:     u16           // Height of the logical screen.
        depth:      u16           // Bit depth declared by the stream.
        loopCount:  u16           // Loop count from the animation extension, zero for endless.
        numFrames:  s32           // Number of frames decoded so far.
        gce:        Gce           // Graphic control extension of the current frame.
        palette:    *Palette?     // Palette the current frame resolves against.
        lct:        Palette       // Local color table of the current frame.
        gct:        Palette       // Global color table of the stream.
        fx:         u16           // Left edge of the current frame in the logical screen.
        fy:         u16           // Top edge of the current frame in the logical screen.
        fw:         u16           // Width of the current frame.
        fh:         u16           // Height of the current frame.
        bgIndex:    u8            // Background color index of the logical screen.
        canvas:     [*] u8?       // Composited logical screen, reused across frames.
        frame:      Array'u8      // Indices of the frame being decoded.
        table:      Table         // LZW dictionary of the current frame.
        animStart:  u64           // Stream offset the animation starts at, for looping.
        animRemain: u64           // Bytes remaining from 'animStart', for looping.
        reachEnd:   bool          // Whether the trailer was reached.
        initDone:   bool          // Whether the header was parsed.

        streamStart: const [*] u8?     // Start of the input, kept for looping.
        stream:      const [*] u8?     // Current read position in the input.
        streamLen:   u64               // Bytes remaining from 'stream'.
        descriptorOffset: u64
        descriptorRemaining: u64
        hasLoopExtension: bool
        reader: ImageReader
        nextIndex: u32
    }
}

impl Decoder
{
    mtd safeStream()->const [*] u8      => cast(const [*] u8) .stream!
    mtd safeStreamStart()->const [*] u8 => cast(const [*] u8) .streamStart!
    mtd safePalette()->*Palette         => cast(*Palette) .palette!
    mtd safeCanvas()->[*] u8            => cast([*] u8) .canvas!
}

public impl Decoder
{
    // Opens an animated GIF for sequential frame decoding.
    //
    // The decoder owns a copy of `buffer`; the caller may release its input after this call.
    mtd open(buffer: const [..] u8) fail
    {
        var reader = ImageReader.decode("image.gif", buffer)
        Swag.drop(me, 1)
        Swag.init(me, 1)
        .reader = #move reader
    }

    internal mtd init(buffer: const [..] u8, decodePixels: bool, readFirst = true) fail
    {
        Swag.drop(me, 1)
        Swag.init(me, 1)

        .streamStart, .stream = buffer.buffer
        .streamLen            = buffer.count

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

        // Color space's depth
        .depth = cast() (((fdsz >> 4) & 7) + 1)

        // Ignore sort flag
        // GCT Size
        .gct.size = fdsz & 0x80 ? 1 << ((fdsz & 0x07) + 1) : 0

        // Background color index
        .bgIndex = .readU8()

        // Aspect ratio
        discard .readU8()

        .read(.gct.colors, 3'u64 * .gct.size)
        .palette = &.gct

        if decodePixels
        {
            let size = cast(u64) .width * cast(u64) .height
            .frame.resize(4 * size)
            let frame = .frame.buffer!
            Memory.set(frame, .bgIndex, size)
            .canvas = &frame[size]

            let bgcolor = cast([*] u8) &.palette.colors[.bgIndex * 3'u32]
            if bgcolor[0] or bgcolor[1] or bgcolor[2]
            {
                for i in size do
                    Memory.copy(&.canvas[i * 3], bgcolor, 3)
            }
        }

        .animStart  = cast(u64) (.stream - .streamStart)
        .animRemain = .streamLen
        .initDone   = true

        if readFirst do discard .getFrame(decodePixels)
    }

    internal mtd prepareFrameImage(image: *Image, decodePixels = true)
    {
        Debug.assert(.initDone)
        image.init(.width, .height, .gce.transparency ? PixelFormat.RGBA8 : PixelFormat.RGB8)
        if !decodePixels do
            return
        image.allocPixels()
    }

    // Decodes the next composited frame into `image`.
    //
    // The image is allocated or reconfigured as needed. Returns false after the GIF
    // trailer has been reached.
    mtd nextFrame(img: *Image)->bool fail
    {
        if .reader.isOpen()
        {
            if .nextIndex >= .reader.info.frames.count do return false
            img[] = .reader.read(.nextIndex)
            .nextIndex += 1
            return true
        }
        Debug.assert(.initDone)
        if .reachEnd do
            return false

        if !.getFrame(true)
        {
            .reachEnd = true
            return false
        }

        let pixelFormat = .gce.transparency ? PixelFormat.RGBA8 : PixelFormat.RGB8
        if !img.isValid() or img.width != .width or img.height != .height or img.pixelFormat != pixelFormat do
            .prepareFrameImage(img)
        .renderFrame(cast([*] u8) img.pixels.buffer!, img.pixelFormat)
        return true
    }

    // Counts the frames in the GIF and rewinds the decoder.
    //
    // GIF does not store this count, so the first call scans the remaining stream.
    mtd frameCount()->s32 fail
    {
        if .reader.isOpen() do return cast(s32) .reader.info.frames.count
        Debug.assert(.initDone)
        if .numFrames do
            return .numFrames

        .numFrames = 1
        while .getFrame(true) do
            .numFrames += 1

        .rewind()
        return .numFrames
    }

    // Rewinds frame iteration to the first frame.
    mtd rewind()
    {
        if .reader.isOpen()
        {
            .nextIndex = 0
            return
        }
        Debug.assert(.initDone)
        .reachEnd  = false
        .stream    = .streamStart + .animStart
        .streamLen = .animRemain
    }
}

public impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => {"GIF - Graphics Interchange Format", ".gif"}

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        var reader = ImageReader.decode("image.gif", buffer, options)
        var result: retval = reader.read(0)
        if options.decodePixels and reader.info.frames[0].pixelFormat == .RGB8 do
            result.convertTo(.RGB8)
        return result
    }
}

struct IndexedFrame
{
    offset: u64
    remaining: u64
    control: Gce
}

struct SetDecoder
{
    decoder: Decoder
    frames: Array'IndexedFrame
}

impl IImageDecoder for SetDecoder
{
    mtd impl format()->ImageFormat => {"GIF - Graphics Interchange Format", ".gif"}
    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        var decoder: Decoder
        let single: IImageDecoder = &decoder
        return single.decode(buffer, options)
    }
}

impl IImageSetDecoder for SetDecoder
{
    mtd impl open(buffer: const [..] u8, options: DecodeOptions)->ImageSetInfo fail
    {
        .frames.clear()
        .decoder.init(buffer, false, false)
        options.checkImage(.decoder.width, .decoder.height, .RGBA8)
        var result: retval
        result.canvasWidth = .decoder.width
        result.canvasHeight = .decoder.height
        if .decoder.bgIndex < .decoder.gct.size
        {
            let color = cast(const [*] u8) &.decoder.gct.colors[cast(u32) .decoder.bgIndex * 3]
            result.background = {r: color[0], g: color[1], b: color[2], a: 255}
        }
        while .decoder.getFrame(false)
        {
            options.checkFrameCount(.frames.count + 1)
            .frames.add({.decoder.descriptorOffset, .decoder.descriptorRemaining, .decoder.gce})
            let control = .decoder.gce
            let frame: ImageFrameInfo = {kind: .Animation, width: .decoder.fw, height: .decoder.fh, x: .decoder.fx, y: .decoder.fy, pixelFormat: control.transparency ? .RGBA8 : .RGB8, durationSeconds: cast(f64) control.delay / 100, disposal: control.disposal == 3 ? .Previous : (control.disposal == 2 ? .Background : .Keep), blend: .Over}
            result.frames.add(frame)
            if result.frames.count == 1 and control.transparency do result.background = {a: 0}
        }
        result.loopCount = .decoder.hasLoopExtension ? (.decoder.loopCount ? cast(u32) .decoder.loopCount + 1 : 0) : 1
        return result
    }

    mtd impl readFrame(index: u32, options: DecodeOptions)->Image fail
    {
        if index >= .frames.count do fail InvalidFormatError{"GIF frame index is out of range"}
        .decoder.stream = .decoder.streamStart + .frames[index].offset
        .decoder.streamLen = .frames[index].remaining
        .decoder.gce = .frames[index].control
        if options.decodePixels do .decoder.frame.resize(cast(u64) .decoder.width * .decoder.height)
        .decoder.readImage(options.decodePixels)
        var result: retval
        result.init(.decoder.fw, .decoder.fh, .decoder.gce.transparency ? .RGBA8 : .RGB8)
        if !options.decodePixels do return result
        result.allocPixels()
        let palette = .decoder.palette!
        for y in result.height
        {
            for x in result.width
            {
                let value = .decoder.frame[cast(u64) (.decoder.fy + y) * .decoder.width + .decoder.fx + x]
                if value >= palette.size do fail InvalidFormatError{"GIF palette index is out of range"}
                let color = &palette.colors[cast(u32) value * 3]
                let target = result.pixels.buffer! + cast(u64) (result.height - y - 1) * result.rowStride + cast(u64) x * result.bytesPerPixel
                Memory.copy(target, color, 3)
                if result.bytesPerPixel == 4 do target[3] = value == .decoder.gce.tindex ? 0'u8 : 255'u8
            }
        }
        return result
    }
}
