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

#[Swag.Opaque]
public struct Decoder
{
    fd:         s32
    width:      u16
    height:     u16
    depth:      u16
    loopCount:  u16
    numFrames:  s32
    gce:        Gce
    palette:    #null *Palette
    lct:        Palette
    gct:        Palette
    fx:         u16
    fy:         u16
    fw:         u16
    fh:         u16
    bgIndex:    u8
    canvas:     #null [*] u8
    frame:      Array'u8
    table:      Table
    animStart:  u64
    animRemain: u64
    reachEnd:   bool
    initDone:   bool

    streamStart: #null const [*] u8
    stream:      #null const [*] u8
    streamLen:   u64
}

impl Decoder
{
    mtd safeStream()->const [*] u8      => cast(const [*] u8) (notnull .stream)
    mtd safeStreamStart()->const [*] u8 => cast(const [*] u8) (notnull .streamStart)
    mtd safePalette()->*Palette         => cast(*Palette) (notnull .palette)
    mtd safeCanvas()->[*] u8            => cast([*] u8) (notnull .canvas)
}

public impl Decoder
{
    // Initialize the decoder
    mtd init(buffer: const [..] u8, decodePixels: bool) fail
    {
        .initDone             = true
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
            let frame = notnull .frame.buffer
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

        discard .getFrame(decodePixels)
    }

    // Create an image for the current frame
    mtd getFrame(image: *Image, decodePixels = true)
    {
        Debug.assert(.initDone)
        image.init(.width, .height, .gce.transparency ? PixelFormat.RGBA8 : PixelFormat.RGB8)
        if !decodePixels do
            return
        image.allocPixels()
    }

    // Get the next frame. Returns false if we have reached the end
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

        .renderFrame(cast([*] u8) (notnull img.pixels.buffer), img.pf)
        return true
    }

    // Returns the number of frames
    // As Gif does not store it, we need to go threw all images (!)
    mtd getNumFrames()->s32 fail
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

    // Restart at frame 0
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
    mtd impl canDecode(fileName: string)->bool
    {
        let ext = Path.getExtensionLowerCase(fileName)
        return ext == ".gif"
    }

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        .init(buffer, options.decodePixels)

        var result: retval
        .getFrame(&result, options.decodePixels)
        if !options.decodePixels do
            return result

        .renderFrame(cast([*] u8) (notnull result.pixels.buffer), result.pf)
        return result
    }
}
