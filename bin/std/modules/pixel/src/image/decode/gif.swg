// :LICENCE
// This code is based on "gifdec" (https://github.com/lecram/gifdec)
// The original code has been modified for Swag

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
        fd:         s32                // Frame delay of the frame being decoded, in hundredths of a second.
        width:      u16                // Width of the logical screen.
        height:     u16                // Height of the logical screen.
        depth:      u16                // Bit depth declared by the stream.
        loopCount:  u16                // Loop count from the animation extension, zero for endless.
        numFrames:  s32                // Number of frames decoded so far.
        gce:        Gce                // Graphic control extension of the current frame.
        palette:    #null *Palette     // Palette the current frame resolves against.
        lct:        Palette            // Local color table of the current frame.
        gct:        Palette            // Global color table of the stream.
        fx:         u16                // Left edge of the current frame in the logical screen.
        fy:         u16                // Top edge of the current frame in the logical screen.
        fw:         u16                // Width of the current frame.
        fh:         u16                // Height of the current frame.
        bgIndex:    u8                 // Background color index of the logical screen.
        canvas:     #null [*] u8       // Composited logical screen, reused across frames.
        frame:      Array'u8           // Indices of the frame being decoded.
        table:      Table              // LZW dictionary of the current frame.
        animStart:  u64                // Stream offset the animation starts at, for looping.
        animRemain: u64                // Bytes remaining from 'animStart', for looping.
        reachEnd:   bool               // Whether the trailer was reached.
        initDone:   bool               // Whether the header was parsed.

        streamStart: #null const [*] u8     // Start of the input, kept for looping.
        stream:      #null const [*] u8     // Current read position in the input.
        streamLen:   u64                    // Bytes remaining from 'stream'.
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
    // The decoder borrows `buffer`; its storage must remain valid until the decoder
    // is no longer used or another buffer is opened.
    mtd open(buffer: const [..] u8) fail
    {
        .init(buffer, true)
    }

    internal mtd init(buffer: const [..] u8, decodePixels: bool) fail
    {
        @drop(me, 1)
        @init(me, 1)

        .streamStart, .stream = @dataof(buffer)
        .streamLen            = @countof(buffer)

        // Header
        var sigver: [3] u8
        .read(sigver, 3)
        if Memory.compare(sigver, @dataof("GIF"), 3) != 0 do
            fail InvalidFormatError{"invalid signature"}

        // Version
        .read(sigver, 3)
        if Memory.compare(sigver, @dataof("89a"), 3) != 0 do
            fail InvalidFormatError{"invalid version"}

        // Width x Height
        .width  = .readU16()
        .height = .readU16()

        // FDSZ
        var fdsz: u8
        .read(&fdsz, 1)
        if !(fdsz & 0x80) do
            fail UnsupportedFormatError{"no global color table"}

        // Color space's depth
        .depth = cast() (((fdsz >> 4) & 7) + 1)

        // Ignore sort flag
        // GCT Size
        .gct.size = 1 << ((fdsz & 0x07) + 1)

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
                for [i] in size do
                    Memory.copy(&.canvas[i * 3], bgcolor, 3)
            }
        }

        .animStart  = cast(u64) (.stream - .streamStart)
        .animRemain = .streamLen
        .initDone   = true

        discard .getFrame(decodePixels)
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
        .init(buffer, options.decodePixels)

        var result: retval
        .prepareFrameImage(&result, options.decodePixels)
        if !options.decodePixels do
            return result

        .renderFrame(cast([*] u8) result.pixels.buffer!, result.pixelFormat)
        return result
    }
}
