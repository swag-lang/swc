//! Format: Animated Portable Network Graphics (APNG) encoder component.
//! Supported: Lossless RGBA8 frames, changed rectangles, rational frame delays, looping, and Adam7 output.
//! Role: This file owns the public APNG writer and its animation chunks.

#global namespace Png

using Core, Core.Errors

private
{
    const TypeAcTl: [4] u8 = ['a', 'c', 'T', 'L']
    const TypeFcTl: [4] u8 = ['f', 'c', 'T', 'L']
    const TypeFdAt: [4] u8 = ['f', 'd', 'A', 'T']

    struct FrameRectangle
    {
        x:      s32
        y:      s32
        width:  s32
        height: s32
    }
}

// Configures animated PNG output.
public struct AnimationOptions
{
    public
    {
        loopCount: u32       // Times the animation plays. Zero repeats indefinitely.
        png:       EncodeOptions     // Filtering, compression, and interlacing used for every frame.
    }
}

// Writes an animated PNG frame by frame.
//
// The writer stores straight RGBA8 pixels and keeps one previous canvas to
// encode changed rectangles. The first frame covers the canvas so a static PNG
// reader can display it. Call [[Pixel.Png.AnimationWriter.end]] to finalize
// the frame count and close the file.
//
// ```swag
// using Pixel
//
// var frame = Image.create(320, 180, .RGBA8)
// var writer = try Png.AnimationWriter.create("animation.apng", frame.width, frame.height)
// frame.fill(Color.fromRgb(24, 32, 48))
// try writer.addFrame(frame, 250)
// frame.fill(Color.fromRgb(72, 149, 239))
// try writer.addFrame(frame, 250)
// try writer.end()
// ```
#[Swag.Opaque, Swag.NoCopy]
public struct AnimationWriter
{
    private
    {
        sink:          ByteSink
        width:         s32
        height:        s32
        count:         u32
        sequence:      u32
        controlOffset: u64
        options:       AnimationOptions
        compressor:    Compress.ZLib
        previous:      Image
        isEnded:       bool
    }
}

public impl AnimationWriter
{
    // Creates or replaces `fileName` with an APNG of the given size in pixels.
    //
    // Dimensions must be positive and the decoded RGBA8 canvas must fit within
    // 2 GiB minus one byte. File failures are reported through `fail`.
    func create(fileName: string, width, height: s32, options: AnimationOptions = {})->AnimationWriter fail
    {
        if width <= 0 or height <= 0
        {
            fail InvalidFormatError{"invalid PNG animation size"}
        }

        if cast(u64, width) * height * 4 > 0x7FFF_FFFF
        {
            fail UnsupportedFormatError{"PNG animation canvas needs more than 2 GiB of decoded pixel memory"}
        }

        var result: #returntype
        result.sink    = try ByteSink.createFile(fileName)
        result.width   = width
        result.height  = height
        result.options = options
        try result.writeAnimationHeader()
        return result
    }

    // Adds a canvas image displayed for `duration / ticksPerSecond` seconds.
    //
    // The denominator must be positive. A zero duration is permitted by APNG.
    // The image must match the canvas size, with packed RGB8, RGBA8, BGR8, or
    // BGRA8 storage. Premultiplied alpha is converted to straight alpha.
    // Invalid input is rejected before writing a frame. An I/O error can leave
    // a partial file and closes the writer's output.
    mtd addFrame(image: Image, duration: u16, ticksPerSecond = 1000_u16) fail
    {
        if not .width or .isEnded
        {
            fail BadParameterError{"PNG animation writer is closed"}
        }

        if not ticksPerSecond
        {
            fail BadParameterError{"PNG animation frame delay denominator is zero"}
        }

        if not image.isValid() or image.pixels.count != image.byteCount or
           image.width != .width or image.height != .height
        {
            fail InvalidFormatError{"invalid PNG animation frame size or pixels"}
        }

        if .count == 0x7FFF_FFFF
        {
            fail UnsupportedFormatError{"PNG animation has too many frames"}
        }

        switch image.pixelFormat
        {
        case .RGB8, .BGR8:
            let rgba   = image.convertedTo(.RGBA8)
            try .encodeFrame(rgba, duration, ticksPerSecond)

        case .RGBA8, .BGRA8:
            if image.alphaMode == .Premultiplied
            {
                let straight = image.convertedAlphaTo(.Straight)
                try .encodeFrame(straight, duration, ticksPerSecond)
            }
            else
            {
                try .encodeFrame(image, duration, ticksPerSecond)
            }

        default:
            fail UnsupportedFormatError{"unsupported PNG animation pixel format"}
        }
    }

    // Finalizes the animation and closes the file.
    //
    // An animation needs at least one frame. An I/O failure can leave a partial file.
    // After success, calling `end` again has no effect.
    mtd end() fail
    {
        if .isEnded
        {
            return
        }

        if not .count
        {
            fail InvalidFormatError{"PNG animation needs at least one frame"}
        }

        var control: [3] u32
        control[0] = Math.nativeToBigEndian(.count)
        control[1] = Math.nativeToBigEndian(.options.loopCount)
        let payload = cast(const [*] u8, &control[0])
        var crc: Hash.Crc32
        crc.update(TypeAcTl)
        crc.update(Swag.makeSlice(payload, 8))
        control[2] = Math.nativeToBigEndian(crc.value())
        try .sink.patch(.controlOffset, Swag.makeSlice(payload, 12))
        try .writeChunk(TypeIEnd, "")
        try .sink.close()
        .previous = {}
        .isEnded = true
    }
}

private impl AnimationWriter
{
    mtd writeChunk(kind: const [4] u8, payload: const [..] u8, prefix: const [..] u8 = "") fail
    {
        let length = prefix.count + payload.count
        try validateChunkLength(length)

        var crc: Hash.Crc32
        crc.update(kind)
        crc.update(prefix)
        crc.update(payload)

        try .sink.writeBigEndian(cast(u32, length))
        try .sink.write(kind)
        try .sink.write(prefix)
        try .sink.write(payload)
        try .sink.writeBigEndian(crc.value())
    }

    mtd writeAnimationHeader() fail
    {
        try .sink.write(PngSignature)
        var header: [13] u8
        Encoder.writeHeaderPayload(&header[0], {width: cast(u32, .width),
                                                height: cast(u32, .height),
                                                bitDepth: 8,
                                                colorType: .AlphaColor,
                                                interlaceMethod: .options.png.interlace ? 1 : 0})
        try .writeChunk(TypeIHdr, header)

        var control: [8] u8
        Encoder.writeU32(&control[4], .options.loopCount)
        .controlOffset = .sink.position() + 8
        try .writeChunk(TypeAcTl, control)
    }

    mtd encodeFrame(image: Image, duration, ticksPerSecond: u16) fail
    {
        let sameFormat = .previous.isValid() and .previous.pixelFormat == image.pixelFormat
        let area = sameFormat ? changedRectangle(.previous, image) : FrameRectangle{width: .width, height: .height}
        let compressed = try Encoder.encodeAnimationFrame(image, area, .options.png, &.compressor)
        try .writeFrame(compressed.toSlice(), area, duration, ticksPerSecond)

        if not sameFormat
        {
            .previous = Image.create(.width, .height, image.pixelFormat, image.pixels.toSlice())
            return
        }

        if area.width == .width and area.height == .height
        {
            Memory.copy(.previous.pixels.storage(), image.pixels.storage(), image.byteCount)
            return
        }

        let start = (cast(u64, .height - area.y - 1) * .previous.rowStride) + cast(u64, area.x) * 4
        let copyBytes = cast(u64, area.width) * 4
        let source = image.pixels.storage() + start
        let destination = .previous.pixels.storage() + start
        for row in area.height
        {
            let offset = cast(u64, row) * .previous.rowStride
            Memory.copy(destination - offset, source - offset, copyBytes)
        }
    }

    func changedRectangle(before, after: Image)->FrameRectangle
    {
        let width  = after.width
        let height = after.height
        let first  = before.pixels.storage()
        let second = after.pixels.storage()
        let topRow = cast(u64, height - 1) * after.rowStride
        let rightColumn = cast(u64, width - 1) * 4
        if cast(const [*] u32, first + topRow)[0] != cast(const [*] u32, second + topRow)[0] and
           cast(const [*] u32, first + rightColumn)[0] != cast(const [*] u32, second + rightColumn)[0]
        {
            return {width: width, height: height}
        }

        var left = width
        var right, top, bottom = -1
        for y in height
        {
            let offset = cast(u64, height - 1 - y) * after.rowStride
            let changed = PackedPixel.changedPackedRow(first + offset, second + offset, after.rowStride, false)
            if changed.right < 0
            {
                continue
            }

            if top < 0
            {
                top = y
            }

            bottom = y
            left = Math.min(left, changed.left / 4)
            right = Math.max(right, changed.right / 4)
        }

        if top < 0
        {
            // Preserve the duration of a repeated image with one unchanged pixel.
            return {width: 1, height: 1}
        }

        return {x: left, y: top, width: right - left + 1, height: bottom - top + 1}
    }

    mtd writeFrame(payload: const [..] u8, area: FrameRectangle, duration, ticksPerSecond: u16) fail
    {
        let first = not .count
        try validateChunkLength(payload.count + (first ? 0 : 4))

        var frame: [26] u8
        Encoder.writeU32(&frame[0], .sequence)
        Encoder.writeU32(&frame[4], cast(u32, area.width))
        Encoder.writeU32(&frame[8], cast(u32, area.height))
        Encoder.writeU32(&frame[12], cast(u32, area.x))
        Encoder.writeU32(&frame[16], cast(u32, area.y))
        frame[20] = Math.byteAt(duration, 1)
        frame[21] = Math.byteAt(duration, 0)
        frame[22] = Math.byteAt(ticksPerSecond, 1)
        frame[23] = Math.byteAt(ticksPerSecond, 0)
        try .writeChunk(TypeFcTl, frame)
        if first
        {
            try .writeChunk(TypeIDat, payload)
            .sequence += 1
        }
        else
        {
            var prefix: [4] u8
            Encoder.writeU32(&prefix[0], .sequence + 1)
            try .writeChunk(TypeFdAt, payload, prefix)
            .sequence += 2
        }

        .count += 1
    }
}
