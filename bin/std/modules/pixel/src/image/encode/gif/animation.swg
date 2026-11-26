//! Format: Graphics Interchange Format (GIF89a) encoder component.
//! Supported: Animations written frame by frame into a file, with a global palette reused for compatible frames, long frame durations, looping, and frames reduced to the rectangle that changed.
//! Not supported: Transparency and interlaced output.
//! Role: This file owns the public animated GIF writer.
//
#global namespace Gif

using Swag, Core, Core.Errors

private const PackRGB = cast(Math.Simd.U8x16, [0'u8, 1, 2, 4, 5, 6, 8, 9, 10, 12, 13, 14, 128, 128, 128, 128])

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
    pendingX:        s32       // Position of the changed area in `previous`, from the top left.
    pendingY:        s32
    pendingWidth:    s32       // Zero width means there is no pending frame.
    pendingHeight:   s32
    pendingDuration: u64      // Time the pending frame is shown so far, in microseconds.
    writtenTime:     u64     // Time covered by the frames written, in microseconds.
    globalTable:     Array!{u8}
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
        if width <= 0 or height <= 0
        {
            fail InvalidFormatError{"invalid animation size"}
        }

        if width > Swag.U16.Max or height > Swag.U16.Max
        {
            fail UnsupportedFormatError{"animation is too big"}
        }

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
        if not image.isValid() or image.pixels.count != image.byteCount
        {
            fail InvalidFormatError{"invalid frame image"}
        }

        if image.width != .width or image.height != .height
        {
            fail InvalidFormatError{"frame size differs from the animation size"}
        }

        if image.pixelFormat != .BGRA8 and
           image.pixelFormat != .RGBA8 and
           image.pixelFormat != .BGR8 and
           image.pixelFormat != .RGB8
        {
            fail UnsupportedFormatError{"unsupported frame pixel format"}
        }

        if .writtenTime > Swag.U64.Max - 5_000
        {
            fail OverflowError{"GIF animation duration exceeds the supported range"}
        }

        let available = Swag.U64.Max - 5_000 - .writtenTime
        if .pendingDuration > available
        {
            fail OverflowError{"GIF animation duration exceeds the supported range"}
        }

        if duration > available - .pendingDuration
        {
            fail OverflowError{"GIF animation duration exceeds the supported range"}
        }

        if not .previous.isValid()
        {
            .rememberFrame(image)
            .setPending(0, 0, .width, .height, duration)
            return
        }

        let area = changedArea(.previous, image)
        if area.width <= 0
        {
            .pendingDuration += duration
            return
        }

        try .flush()
        .rememberFrame(image)
        .setPending(area.x, area.y, area.width, area.height, duration)
    }

    // Writes the last frame and the trailer, and closes the file.
    mtd end() fail
    {
        if .isEnded
        {
            return
        }

        .isEnded = true

        try .flush()
        if .globalTable.isEmpty()
        {
            try .writeHeader()
        }

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
        let packed = .globalTable.isEmpty() ? 0_u8 : 0x80_u8 | ((.globalBits - 1) << 4) | (.globalBits - 1)
        try .sink.write([packed, 0, 0])
        if not .globalTable.isEmpty()
        {
            try .sink.write(.globalTable.toSlice())
        }

        if .loopCount != 1
        {
            try .sink.write([0x21_u8, 0xFF, 0x0B])
            try .sink.write("NETSCAPE2.0")
            try .sink.write([0x03_u8, 0x01])
            let repeatCount = .loopCount ? .loopCount - 1 : 0_u16
            try .sink.writeLittleEndian(repeatCount)
            try .sink.writeByte(0)
        }
    }

    // Owns a snapshot even if the caller changes the image before the frame is flushed.
    mtd rememberFrame(image: Image)
    {
        if not .previous.isValid() or .previous.pixelFormat != image.pixelFormat do
            .previous = Image.create(image.width, image.height, image.pixelFormat, image.pixels.toSlice(), image.alphaMode)
        else do
            Memory.copy(.previous.pixels.storage(), image.pixels.storage(), image.byteCount)
    }

    mtd setPending(x, y, w, h: s32, duration: u64)
    {
        .pendingX        = x
        .pendingY        = y
        .pendingWidth    = w
        .pendingHeight   = h
        .pendingDuration = duration
    }

    // Writes the pending area as one frame, its delay rounded so the total duration stays exact.
    mtd flush() fail
    {
        if not .pendingWidth do
            return
        }

        let endTime = .writtenTime + .pendingDuration
        let delay   = Math.max((endTime + 5_000) / 10_000 - (.writtenTime + 5_000) / 10_000, 2_u64)
        .writtenTime = endTime

        var palette   = Encoder.buildPaletteRegion(.previous, .pendingX, .pendingY, .pendingWidth, .pendingHeight, false, .dither)
        var block: ConcatBuffer
        var useGlobal = true
        if .globalTable.isEmpty()
        {
            var colorTable: ConcatBuffer
            Encoder.writeColorTable(&colorTable, palette)
            colorTable.makeLinear()
            .globalTable.add(unwrap colorTable.toSlice())
            .globalBits = palette.tableBits
            try .writeHeader()
        }
        else
        {
            if .globalBits >= 6 and .globalColorMap.isEmpty() do
                .globalColorMap = Encoder.buildColorIndexMap(.globalTable.toSlice())
            useGlobal = Encoder.remapToColorTable(&palette, .globalTable.toSlice(), .globalColorMap.toSlice())
        }

        // Keep the control extension and image payload in the same buffered write.
        block.addBytes([0x21'u8, 0xF9, 0x04, 0x04, 0, 0, 0, 0])

        // Image descriptor, with a local colour table only when the global one lacks a colour.
        block.addNative(0x2C_u8)
        Encoder.writeU16(&block, cast(u16, .pendingX))
        Encoder.writeU16(&block, cast(u16, .pendingY))
        Encoder.writeU16(&block, cast(u16, .pendingWidth))
        Encoder.writeU16(&block, cast(u16, .pendingHeight))
        block.addNative(useGlobal ? 0'u8 : 0x80'u8 | (palette.tableBits - 1))
        if not useGlobal do
            Encoder.writeColorTable(&block, palette)
        let codeSize = useGlobal ? Math.max(.globalBits, 2'u8) : palette.lzwMinCodeSize
        block.addNative(codeSize)

        let compressed = Encoder.lzwCompress(palette.indexes.toSlice(), codeSize, palette.count == 1)
        Encoder.writeSubBlocks(&block, compressed.toSlice())

        block.makeLinear()
        let picture   = unwrap block.toSlice()
        var remaining = delay
        while remaining
        {
            var chunk = Math.min(remaining, cast(u64, Swag.U16.Max))
            if remaining - chunk == 1
            {
                chunk -= 1
            }

            // Disposal mode 1 keeps the picture; another copy carries time beyond 655.35 seconds.
            picture[4] = cast #wrap(u8, chunk)
            picture[5] = cast(u8, chunk >> 8)
            try .sink.write(picture)
            remaining -= chunk
        }

        .pendingWidth = 0
    }

    #[Inline]
    func changedByteMask(first, second: const [*] u8, channels: u32)->u32
    {
        let equal = Math.Simd.load(first) == Math.Simd.load(second)
        return ~Math.Simd.bitmask(equal) & channels
    }

    // Finds the first and last byte of a changed RGB channel in one packed row.
    func changedPackedRow(first, second: const [*] u8, rowBytes: s32, alpha: bool)->{ left, right: s32 }
    {
        let channels  = alpha ? 0x7777'u32 : 0xFFFF'u32
        let vectorEnd = rowBytes & ~15
        var start     = 0
        var mask: u32
        while start < vectorEnd
        {
            mask = changedByteMask(first + start, second + start, channels)
            if mask do
                break
            start += 16
        }

        var left  = mask ? start + cast(s32, Math.trailingZeros(mask)) : rowBytes
        var right = -1
        for offset in vectorEnd until rowBytes
        {
            if (alpha and (offset & 3) == 3) or first[offset] == second[offset] do
                continue
            if left == rowBytes do
                left = offset
            right = offset
        }

        if right >= 0 or not mask do
            return {left, right}

        // The earliest changed group already supplies both bounds when no later group differs.
        var stop = vectorEnd - 16
        while stop > start
        {
            let last = changedByteMask(first + stop, second + stop, channels)
            if last do
                return {left, stop + 31 - cast(s32, Math.leadingZeros(last))}
            stop -= 16
        }

        return {left, start + 31 - cast(s32, Math.leadingZeros(mask))}
    }

    #[Inline]
    func channelsDiffer(first, second: const [*] u8, swap: bool)->bool
    {
        let red  = swap ? 2 : 0
        let blue = 2 - red
        return first[0] != second[red] or first[1] != second[1] or first[2] != second[blue]
    }

    // Compares packed RGB channels with different pixel strides or channel orders.
    func changedMixedRow(first, second: const [*] u8, width: s32, firstStep, secondStep: u8, swap: bool)->{ left, right: s32 }
    {
        const CopyRGB = cast(Math.Simd.U8x16, [0'u8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 128, 128, 128, 128])
        const SwapRGB = cast(Math.Simd.U8x16, [2'u8, 1, 0, 5, 4, 3, 8, 7, 6, 11, 10, 9, 128, 128, 128, 128])
        const PackBGR = cast(Math.Simd.U8x16, [2'u8, 1, 0, 6, 5, 4, 10, 9, 8, 14, 13, 12, 128, 128, 128, 128])
        let firstOrder  = firstStep == 4 ? PackRGB : CopyRGB
        let secondOrder = secondStep == 4 ? (swap ? PackBGR : PackRGB) : (swap ? SwapRGB : CopyRGB)
        var left        = width
        var right       = -1
        var x           = 0
        while width - x >= 6
        {
            let a = Math.Simd.shuffle(Math.Simd.load(first + x * firstStep), firstOrder)
            let b = Math.Simd.shuffle(Math.Simd.load(second + x * secondStep), secondOrder)
            let changes = ~Math.Simd.bitmask(a == b) & 0xFFF
            if changes
            {
                if right < 0 do
                    left = x + cast(s32, Math.trailingZeros(changes)) / 3
                right = x + (31 - cast(s32, Math.leadingZeros(changes))) / 3
            }
            x += 4
        }

        for tail in x until width
        {
            let a = first + tail * firstStep
            let b = second + tail * secondStep
            if not channelsDiffer(a, b, swap) do
                continue
            if right < 0 do
                left = tail
            right = tail
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
        let swap         = beforeBgr != afterBgr

        // Opposite changed corners already establish every side of the bounding rectangle.
        let topRow = cast(u64, after.height - 1)
        if channelsDiffer(first + topRow * before.rowStride, second + topRow * after.rowStride, swap)
        {
            let rightColumn = cast(u64, after.width - 1)
            if channelsDiffer(first + rightColumn * before.bytesPerPixel,
                              second + rightColumn * after.bytesPerPixel, swap) do
                return {0, 0, after.width, after.height}
        }

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
                let changed = changedMixedRow(firstRow, secondRow, after.width, before.bytesPerPixel, after.bytesPerPixel, swap)
                if changed.right < 0 do
                    continue
                rowLeft  = changed.left
                rowRight = changed.right
            }

            if rowLeft < 0
            {
                continue
            }

            if top < 0
            {
                top = y
            }

            bottom = y
            left   = Math.min(left, rowLeft)
            right  = Math.max(right, rowRight)
        }

        if top < 0
        {
            return {0, 0, 0, 0}
        }

        return {left, top, right - left + 1, bottom - top + 1}
    }
}
