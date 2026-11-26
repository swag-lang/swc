//! Format: Graphics Interchange Format (GIF89a) encoder component.
//! Supported: Animations written frame by frame into a file, with a global palette reused for compatible frames, long frame durations, looping, and frames reduced to the rectangle that changed.
//! Not supported: Transparency and interlaced output.
//! Role: This file owns the public animated GIF writer.
//
#global namespace Gif

using Swag, Core, Core.Errors

// Configures an animated GIF.
public struct AnimationOptions
{
    public loopCount: u16 = 0     // Times the animation plays; zero plays it forever.
    public dither:    bool        // Apply ordered colour dithering when a frame needs quantization; off by default.
}

// Writes an animated GIF frame by frame, without holding the animation in memory.
//
// Frames are opaque: their alpha channel is ignored. The first frame supplies a global palette;
// later frames reuse it when their colours occur in that table, or carry their own palette. Only
// the rectangle that changed since the previous frame is stored. A frame identical to the previous
// one lengthens it instead of adding a frame. GIF counts time in
// hundredths of a second; the writer carries the rounding from frame to frame and repeats a frame
// when a still interval exceeds GIF's 655.35-second delay limit, so long pauses retain their time.
//
// [[Pixel.Gif.AnimationWriter.end]] writes what is still pending and finishes the file, so its failure
// must be handled.
#[Swag.NoCopy]
public struct AnimationWriter
{
    sink:            ByteSink
    width:           s32
    height:          s32
    previous:        Image     // Last frame added, compared with the next one.
    pending:         Image     // Changed area of the last frame, waiting for its duration.
    pendingX:        s32       // Position of `pending` in the frame, from the top left.
    pendingY:        s32
    pendingDuration: u64     // Time `pending` is shown so far, in microseconds.
    writtenTime:     u64     // Time covered by the frames written, in microseconds.
    globalTable:     Array'u8
    globalBits:      u8
    loopCount:       u16
    dither:          bool
    isEnded:         bool
}

public impl AnimationWriter
{
    // Creates `fileName` for an animation of `width` by `height` pixels.
    //
    // The header is written when the first frame is flushed, after its global colour table is known.
    func create(fileName: string, width, height: s32, options: AnimationOptions = {})->AnimationWriter fail
    {
        if width <= 0 or height <= 0 do
            fail InvalidFormatError{"invalid animation size"}
        if width > Swag.U16.Max or height > Swag.U16.Max do
            fail UnsupportedFormatError{"animation is too big"}

        return AnimationWriter{sink: try ByteSink.createFile(fileName),
                               width: width,
                               height: height,
                               loopCount: options.loopCount,
                               dither: options.dither}
    }

    // Adds `image`, shown for `duration` microseconds.
    //
    // The image must have the size of the animation, in an 8-bit RGB or BGR format with or without
    // alpha, with a complete pixel buffer. Durations that overflow the animation's microsecond
    // clock are rejected before the frame is accepted.
    mtd addFrame(image: Image, duration: u64) fail
    {
        Swag.assert(not .isEnded)
        if not image.isValid() or image.pixels.count != image.byteCount do
            fail InvalidFormatError{"invalid frame image"}
        if image.width != .width or image.height != .height do
            fail InvalidFormatError{"frame size differs from the animation size"}
        if image.pixelFormat != .BGRA8 and
           image.pixelFormat != .RGBA8 and
           image.pixelFormat != .BGR8 and
           image.pixelFormat != .RGB8 do
            fail UnsupportedFormatError{"unsupported frame pixel format"}
        if .writtenTime > Swag.U64.Max - 5_000 do
            fail OverflowError{"GIF animation duration exceeds the supported range"}
        let available = Swag.U64.Max - 5_000 - .writtenTime
        if .pendingDuration > available do
            fail OverflowError{"GIF animation duration exceeds the supported range"}
        if duration > available - .pendingDuration do
            fail OverflowError{"GIF animation duration exceeds the supported range"}

        if not .previous.isValid()
        {
            .previous = image
            .setPending(image, 0, 0, .width, .height, duration)
            return
        }

        let area = changedArea(.previous, image)
        if area.width <= 0
        {
            .pendingDuration += duration
            return
        }

        try .flush()
        .previous = image
        .setPending(image, area.x, area.y, area.width, area.height, duration)
    }

    // Writes the last frame and the trailer, and closes the file.
    mtd end() fail
    {
        if .isEnded do
            return
        .isEnded = true

        try .flush()
        if .globalTable.isEmpty() do
            try .writeHeader()
        try .sink.writeByte(0x3B)
        try .sink.close()
    }
}

private impl AnimationWriter
{
    // Writes the logical screen and loop count once the first frame's palette is known.
    mtd writeHeader() fail
    {
        try .sink.write("GIF89a")
        try .sink.writeLittleEndian(cast(u16, .width))
        try .sink.writeLittleEndian(cast(u16, .height))
        let packed = .globalTable.isEmpty() ? 0'u8 : 0x80'u8 | ((.globalBits - 1) << 4) | (.globalBits - 1)
        try .sink.write([packed, 0, 0])
        if not .globalTable.isEmpty() do
            try .sink.write(.globalTable.toSlice())

        if .loopCount != 1
        {
            try .sink.write([0x21'u8, 0xFF, 0x0B])
            try .sink.write("NETSCAPE2.0")
            try .sink.write([0x03'u8, 0x01])
            let repeatCount = .loopCount ? .loopCount - 1 : 0'u16
            try .sink.writeLittleEndian(repeatCount)
            try .sink.writeByte(0)
        }
    }

    // Keeps the area of `image` at `x, y` waiting for its duration, without its alpha channel.
    mtd setPending(image: Image, x, y, w, h: s32, duration: u64)
    {
        let opaque = image.pixelFormat == .BGRA8 ? PixelFormat.BGR8 : image.pixelFormat == .RGBA8 ? PixelFormat.RGB8 : image.pixelFormat
        .pending = Image.create(w, h, opaque)

        let sourcePixel = image.bytesPerPixel
        let targetBytes = cast(u64, .pending.rowStride)
        let sourceRow   = image.pixels.storage() + cast(u64, image.height - y - h) * image.rowStride + cast(u64, x) * sourcePixel
        let targetRow   = .pending.pixels.storage()
        if sourcePixel == 3 and w == image.width
        {
            Memory.copy(targetRow, sourceRow, .pending.byteCount)
        }
        else
        {
            const PackRGB = [0'u8, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14, 0x80, 0x80, 0x80, 0x80]
            let groups = cast(u64, w) / 4
            for row in h
            {
                let source = sourceRow + cast(u64, row) * image.rowStride
                let target = targetRow + cast(u64, row) * targetBytes
                if sourcePixel == 3
                {
                    Memory.copy(target, source, targetBytes)
                    continue
                }

                for group in groups
                {
                    let bytes  = Math.Simd.load(source + group * 16)
                    let packed = Math.Simd.shuffle(bytes, cast(Math.Simd.U8x16, PackRGB))
                    let output = target + group * 12
                    Math.Simd.storeLow8(output, packed)
                    cast([*] u32, output + 8)[0] = cast #bit(Math.Simd.U32x4, packed)[2]
                }

                for column in groups * 4 until cast(u64, w) do
                    Memory.copy(target + column * 3, source + column * 4, 3)
            }
        }

        .pendingX        = x
        .pendingY        = y
        .pendingDuration = duration
    }

    // Writes the pending area as one frame, its delay rounded so the total duration stays exact.
    mtd flush() fail
    {
        if not .pending.isValid() do
            return

        let endTime = .writtenTime + .pendingDuration
        let delay   = Math.max((endTime + 5_000) / 10_000 - (.writtenTime + 5_000) / 10_000, 2'u64)
        .writtenTime = endTime

        var palette = Encoder.buildPalette(.pending, .dither)
        var block:      ConcatBuffer
        var colorTable: ConcatBuffer
        Encoder.writeColorTable(&colorTable, palette)
        colorTable.makeLinear()
        let colors = unwrap colorTable.toSlice()

        var useGlobal = not .globalTable.isEmpty() and
                        Encoder.remapToColorTable(&palette, .globalTable.toSlice())
        if .globalTable.isEmpty()
        {
            .globalTable.add(colors)
            .globalBits = palette.tableBits
            try .writeHeader()
            useGlobal = true
        }

        // Image descriptor, with a local colour table only when the global one lacks a colour.
        block.addNative(0x2C'u8)
        Encoder.writeU16(&block, cast(u16, .pendingX))
        Encoder.writeU16(&block, cast(u16, .pendingY))
        Encoder.writeU16(&block, cast(u16, .pending.width))
        Encoder.writeU16(&block, cast(u16, .pending.height))
        block.addNative(useGlobal ? 0'u8 : 0x80'u8 | (palette.tableBits - 1))
        if not useGlobal do
            block.addBytes(colors)
        let codeSize = useGlobal ? Math.max(.globalBits, 2'u8) : palette.lzwMinCodeSize
        block.addNative(codeSize)

        let compressed = Encoder.lzwCompress(palette.indexes.toSlice(), codeSize)
        Encoder.writeSubBlocks(&block, compressed.toSlice())

        block.makeLinear()
        let picture   = unwrap block.toSlice()
        var remaining = delay
        while remaining
        {
            var chunk = Math.min(remaining, cast(u64, Swag.U16.Max))
            if remaining - chunk == 1 do
                chunk -= 1

            // Disposal mode 1 keeps the picture; another copy carries time beyond 655.35 seconds.
            try .sink.write([0x21'u8, 0xF9, 0x04, 0x04])
            try .sink.writeLittleEndian(cast(u16, chunk))
            try .sink.write([0'u8, 0])
            try .sink.write(picture)
            remaining -= chunk
        }

        .pending.release()
    }

    // Finds the first and last byte of a changed RGB channel in one packed row.
    func changedPackedRow(first, second: const [*] u8, rowBytes: s32, alpha: bool)->{ left, right: s32 }
    {
        let channels  = alpha ? 0x7777'u32 : 0xFFFF'u32
        let vectorEnd = rowBytes & ~15
        var left      = rowBytes
        var right     = -1
        for group in vectorEnd / 16
        {
            let offset  = group * 16
            let equal   = Math.Simd.load(first + offset) == Math.Simd.load(second + offset)
            let changed = ~Math.Simd.bitmask(equal) & channels
            if not changed do
                continue
            if right < 0 do
                left = offset + cast(s32, Math.trailingZeros(changed))
            right = offset + 31 - cast(s32, Math.leadingZeros(changed))
        }

        for offset in vectorEnd until rowBytes
        {
            if (alpha and (offset & 3) == 3) or first[offset] == second[offset] do
                continue
            if right < 0 do
                left = offset
            right = offset
        }

        return {left, right}
    }

    // Returns the smallest rectangle holding every pixel whose colour differs, alpha ignored.
    func changedArea(before, after: Image)->{ x: s32, y: s32, width: s32, height: s32 }
    {
        let first        = before.pixels.storage()
        let second       = after.pixels.storage()
        let sameFormat   = before.pixelFormat == after.pixelFormat
        let beforeBgr    = before.pixelFormat == .BGR8 or before.pixelFormat == .BGRA8
        let afterBgr     = after.pixelFormat == .BGR8 or after.pixelFormat == .BGRA8
        let firstChannel = beforeBgr == afterBgr ? 0 : 2
        let lastChannel  = 2 - firstChannel

        var left   = after.width
        var right  = -1
        var top    = -1
        var bottom = -1
        for y in after.height
        {
            let row       = after.height - 1 - y
            let firstRow  = first + cast(u64, row) * before.rowStride
            let secondRow = second + cast(u64, row) * after.rowStride
            var rowLeft   = after.width
            var rowRight  = -1
            if sameFormat
            {
                let changed = changedPackedRow(firstRow, secondRow, after.rowStride, after.bytesPerPixel == 4)
                if changed.right < 0 do
                    continue
                rowLeft  = changed.left / after.bytesPerPixel
                rowRight = changed.right / after.bytesPerPixel
            }
            else
            {
                var a = firstRow
                var b = secondRow
                for x in after.width
                {
                    if a[0] != b[firstChannel] or a[1] != b[1] or a[2] != b[lastChannel]
                    {
                        if rowRight < 0 do
                            rowLeft = x
                        rowRight = x
                    }

                    a += before.bytesPerPixel
                    b += after.bytesPerPixel
                }

                if rowRight < 0 do
                    continue
            }

            if top < 0 do
                top = y
            bottom = y
            left   = Math.min(left, rowLeft)
            right  = Math.max(right, rowRight)
        }

        if top < 0 do
            return {0, 0, 0, 0}
        return {left, top, right - left + 1, bottom - top + 1}
    }
}
