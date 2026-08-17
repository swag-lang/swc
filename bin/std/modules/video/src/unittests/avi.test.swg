#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel

// One colour of the quadrant frame the encoding tests compress.
private struct AviColor
{
    r, g, b: u8
}

// The four quadrants, in the order the top-left corner of a frame reaches them.
private const AviQuadrants: [4] AviColor = [{255, 0, 0}, {0, 255, 0}, {0, 0, 255}, {255, 255, 255}]

// Returns the quadrant colour at the top-left coordinates `x, y` of a frame of `size` pixels.
private func aviQuadrantColor(size, x, y: s32)->AviColor
{
    return AviQuadrants[(y < size / 2 ? 0 : 2) + (x < size / 2 ? 0 : 1)]
}

// Returns a frame of four solid quadrants.
//
// Solid blocks are what makes a lossy round trip provable: the middle of a quadrant is far
// enough from every edge that compressing it and reading it back cannot move it much, while
// four different quadrants still prove the frame was not turned over or transposed.
private func aviQuadrantImage(size: s32)->Image
{
    var result: retval = Image.create(size, size, .RGB8)
    for y in size
    {
        for x in size
        {
            let color = aviQuadrantColor(size, x, y)
            let pixel = result.pixels.buffer! + cast(u64) (size - y - 1) * cast(u64) result.rowStride + cast(u64) x * 3
            pixel[0] = color.r
            pixel[1] = color.g
            pixel[2] = color.b
        }
    }

    return result
}

// Asserts that `frame` is the quadrant frame, sampled at the middle of each quadrant.
private func aviAssertQuadrants(frame: Image, size: s32, tolerance: s32)
{
    let samples: [2] s32 = [size / 4, size - size / 4 - 1]
    for y in samples
    {
        for x in samples
        {
            let color = aviQuadrantColor(size, x, y)
            videoAssertColor(frame.pixelColor(x, y), color.r, color.g, color.b, tolerance)
        }
    }
}

// Returns the little-endian 32-bit value the container stores at `offset`.
private func aviReadU32(bytes: const [..] u8, offset: u64)->u32
{
    var result = 0'u32
    for shift in 4 do
        result |= cast(u32) bytes[offset + cast(u64) shift] << cast(u32) (shift * 8)
    return result
}

// Reports whether the four characters of `id` sit at `offset`.
private func aviHasId(bytes: const [..] u8, offset: u64, id: string)->bool
{
    for index in 4 where bytes[offset + cast(u64) index] != id[index] do
        return false
    return true
}

// Assembles an AVI file byte by byte.
//
// A decoding test needs to state exactly what a container says, including the things no encoder
// writes: an index counted from the file rather than from the frame list, a frame chunk with no
// payload, a codec nothing supports.
private struct AviWriter
{
    bytes: Array'u8
}

private impl AviWriter
{
    // Appends one little-endian 16-bit value.
    mtd addU16(value: u16)
    {
        .bytes.add(cast(u8) (value & 0xFF))
        .bytes.add(cast(u8) (value >> 8))
    }

    // Appends one little-endian 32-bit value.
    mtd addU32(value: u32)
    {
        for shift in 4 do
            .bytes.add(cast(u8) ((value >> cast(u32) (shift * 8)) & 0xFF))
    }

    // Appends the four characters of a chunk identifier.
    mtd addId(id: string)
    {
        for index in 4 do
            .bytes.add(id[index])
    }

    // Opens a chunk and returns where its size field went.
    mtd beginChunk(id: string)->u64
    {
        .addId(id)
        let result = .bytes.count
        .addU32(0)
        return result
    }

    // Closes the chunk whose size field is at `at`, and pads an odd payload the way RIFF does.
    mtd endChunk(at: u64)
    {
        let size  = .bytes.count - at - 4
        let value = cast(u32) size
        for shift in 4 do
            .bytes[at + cast(u64) shift] = cast(u8) ((value >> cast(u32) (shift * 8)) & 0xFF)
        if size & 1 do
            .bytes.add(0)
    }
}

// The container a decoding test builds, and the frames it holds.
private struct AviCase
{
    width:           s32    = 2
    height:          s32    = 2
    streamKind:      string = "vids"
    compression:     string = "DIB "
    bitCount:        u16    = 24
    scale:           u32    = 1
    rate:            u32    = 25
    isTopDown:       bool
    hasIndex:        bool   = true
    isIndexAbsolute: bool
    isGrouped:       bool
    frames:          Array'(Array'u8)
}

private impl AviCase
{
    // Adds one frame payload, exactly as the container will store it.
    mtd addFrame(payload: const [..] u8)
    {
        var frame: Array'u8
        frame.add(payload)
        .frames.add(#move frame)
    }

    // Adds one frame that carries no picture, which is how the container repeats the previous one.
    mtd addRepeatedFrame()
    {
        var frame: Array'u8
        .frames.add(#move frame)
    }

    // Returns the bytes of the described file.
    mtd build()->Array'u8
    {
        var file: AviWriter
        let riff = file.beginChunk("RIFF")
        file.addId("AVI ")
        .writeHeaderList(&file)

        var offsets: Array'u64
        let list      = file.beginChunk("LIST")
        let frameList = file.bytes.count
        file.addId("movi")
        for position in .frames.count
        {
            // An OpenDML file wraps each set of frames in a `rec ` list, so the walk has to
            // descend one level to reach them.
            let group = .isGrouped ? file.beginChunk("LIST") : 0
            if .isGrouped do
                file.addId("rec ")

            let frame = &.frames[position]
            offsets.add(file.bytes.count)
            let chunk = file.beginChunk("00db")
            file.bytes.add(frame.toSlice())
            file.endChunk(chunk)
            if .isGrouped do
                file.endChunk(group)
        }

        file.endChunk(list)
        if .hasIndex
        {
            let table = file.beginChunk("idx1")
            for offset, position in offsets
            {
                file.addId("00db")
                file.addU32(0x10)
                file.addU32(cast(u32) (.isIndexAbsolute ? offset : offset - frameList))
                file.addU32(cast(u32) .frames[position].count)
            }

            file.endChunk(table)
        }

        file.endChunk(riff)
        return #move file.bytes
    }

    // Writes the `hdrl` list, which describes the file and its single stream.
    private mtd writeHeaderList(file: *AviWriter)
    {
        let list = file.beginChunk("LIST")
        file.addId("hdrl")

        let main = file.beginChunk("avih")
        file.addU32(1_000_000 * .scale / .rate)
        file.addU32(0)
        file.addU32(0)
        file.addU32(.hasIndex ? 0x10 : 0)
        file.addU32(cast(u32) .frames.count)
        file.addU32(0)
        file.addU32(1)
        file.addU32(0)
        file.addU32(cast(u32) .width)
        file.addU32(cast(u32) .height)
        for 4 do
            file.addU32(0)
        file.endChunk(main)

        let stream = file.beginChunk("LIST")
        file.addId("strl")
        .writeStreamHeader(file)
        .writeFormatHeader(file)
        file.endChunk(stream)

        file.endChunk(list)
    }

    // Writes the `strh` chunk of the stream.
    private mtd writeStreamHeader(file: *AviWriter)
    {
        let chunk = file.beginChunk("strh")
        file.addId(.streamKind)
        .writeCompression(file)
        file.addU32(0)
        file.addU16(0)
        file.addU16(0)
        file.addU32(0)
        file.addU32(.scale)
        file.addU32(.rate)
        file.addU32(0)
        file.addU32(cast(u32) .frames.count)
        file.addU32(0)
        file.addU32(0)
        file.addU32(0)
        for 4 do
            file.addU16(0)
        file.endChunk(chunk)
    }

    // Writes the codec identifier, which the `BI_RGB` spelling stores as a zero rather than a name.
    private mtd writeCompression(file: *AviWriter)
    {
        if !@countof(.compression) do
            file.addU32(0)
        else do
            file.addId(.compression)
    }

    // Writes the `strf` chunk, which is the bitmap header describing the frames.
    private mtd writeFormatHeader(file: *AviWriter)
    {
        // A top-down frame is spelled with a negative height, which the field stores as bits.
        let stored = .isTopDown ? 0 - .height : .height
        let chunk  = file.beginChunk("strf")
        file.addU32(40)
        file.addU32(cast(u32) .width)
        file.addU32(cast #bit (u32) stored)
        file.addU16(1)
        file.addU16(.bitCount)
        .writeCompression(file)
        file.addU32(0)
        file.addU32(0)
        file.addU32(0)
        file.addU32(0)
        file.addU32(0)
        file.endChunk(chunk)
    }
}

// One uncompressed 2x2 frame, stored the way a bitmap stores it: blue and white on the top row,
// red and green below, each row padded from six bytes to eight.
private const AviBottomUpFrame: [16] u8 = [
    0, 0, 255, 0, 255, 0, 0, 0,
    255, 0, 0, 255, 255, 255, 0, 0]

// The same frame with its two rows exchanged, so the two row orders decode to the same picture.
private const AviTopDownFrame: [16] u8 = [
    255, 0, 0, 255, 255, 255, 0, 0,
    0, 0, 255, 0, 255, 0, 0, 0]

// Asserts that `frame` is the picture both 2x2 fixtures describe.
private func aviAssertCornerFrame(frame: Image)
{
    videoAssertColor(frame.pixelColor(0, 0), 0, 0, 255, tolerance: 0)
    videoAssertColor(frame.pixelColor(1, 0), 255, 255, 255, tolerance: 0)
    videoAssertColor(frame.pixelColor(0, 1), 255, 0, 0, tolerance: 0)
    videoAssertColor(frame.pixelColor(1, 1), 0, 255, 0, tolerance: 0)
}

// A clip encoded as Motion JPEG reads back as the picture it was built from, and the container
// around it says what the frames say.
#test
{
    const Size = 16's32
    let rate = expect FrameRate.create(30, 1)
    var clip = expect Clip.create(Size, Size, rate)
    expect clip.addFrame(aviQuadrantImage(Size))
    expect clip.addFrame(videoGrayImage(Size, Size, 200))

    let bytes  = expect clip.encodeToBytes("clip.avi")
    var reader = expect Reader.openMemory("clip.avi", bytes.toSlice())
    @assert(reader.width() == Size and reader.height() == Size)
    @assert(reader.frameRate() == rate)
    @assert(reader.frameCount() == 2)
    @assert(reader.streamFormat().extensions == ".avi")
    @assert(Math.isEqualEpsilon(reader.durationInSeconds(), 2.0 / 30.0, 0.0001))

    // Reading the second frame first proves the index, not the order frames were written in.
    let second = expect reader.decodeFrame(1)
    videoAssertColor(second.pixelColor(Size / 2, Size / 2), 200, 200, 200, tolerance: 10)

    let first = expect reader.decodeFrame(0)
    aviAssertQuadrants(first, Size, tolerance: 10)
}

// The encoded container is a real AVI file: the totals its header carries are the ones the
// finished stream measured, and they are checked here without this module's own decoder.
#test
{
    let rate = expect FrameRate.create(24, 1)
    var clip = expect Clip.create(8, 4, rate)
    expect clip.addFrame(videoGrayImage(8, 4, 64))
    expect clip.addFrame(videoGrayImage(8, 4, 192))
    expect clip.addFrame(videoGrayImage(8, 4, 255))

    let bytes = expect clip.encodeToBytes("totals.avi")
    let raw   = bytes.toSlice()
    @assert(aviHasId(raw, 0, "RIFF") and aviHasId(raw, 8, "AVI "))
    @assert(aviHasId(raw, 12, "LIST") and aviHasId(raw, 20, "hdrl"))
    @assert(aviHasId(raw, 24, "avih") and aviHasId(raw, 100, "strh") and aviHasId(raw, 164, "strf"))
    @assert(aviHasId(raw, 212, "LIST") and aviHasId(raw, 220, "movi") and aviHasId(raw, 224, "00dc"))

    // Everything the header could only know once the last frame landed.
    @assert(aviReadU32(raw, 4) == cast(u32) bytes.count - 8)
    @assert(aviReadU32(raw, 48) == 3)       // Frame count of the file header.
    @assert(aviReadU32(raw, 64) == 8)       // Frame width of the file header.
    @assert(aviReadU32(raw, 68) == 4)       // Frame height of the file header.
    @assert(aviReadU32(raw, 128) == 1)      // Rate denominator of the stream header.
    @assert(aviReadU32(raw, 132) == 24)     // Rate numerator of the stream header.
    @assert(aviReadU32(raw, 140) == 3)      // Frame count of the stream header.

    // The size of the frame list is what places the index right after the last frame.
    let indexStart = 220 + cast(u64) aviReadU32(raw, 216)
    @assert(aviHasId(raw, indexStart, "idx1"))
    @assert(aviReadU32(raw, indexStart + 4) == 3 * 16)
    @assert(aviHasId(raw, indexStart + 8, "00dc"))
    @assert(aviReadU32(raw, indexStart + 16) == 4)
    @assert(indexStart + 8 + 3 * 16 == bytes.count)
}

// Uncompressed frames decode from the padded bitmap rows the container stores, in both row
// orders, and the two orders describe the same picture.
#test
{
    var bottomUp: AviCase
    bottomUp.addFrame(AviBottomUpFrame)
    let bottomUpBytes = bottomUp.build()

    var reader = expect Reader.openMemory("bottom-up.avi", bottomUpBytes.toSlice())
    @assert(reader.width() == 2 and reader.height() == 2 and reader.frameCount() == 1)
    @assert(reader.frameRate() == expect FrameRate.create(25, 1))
    aviAssertCornerFrame(expect reader.decodeFrame(0))

    var topDown: AviCase
    topDown.isTopDown = true
    topDown.addFrame(AviTopDownFrame)
    let topDownBytes = topDown.build()

    var flipped = expect Reader.openMemory("top-down.avi", topDownBytes.toSlice())
    aviAssertCornerFrame(expect flipped.decodeFrame(0))
}

// A row is padded to a multiple of four bytes whatever the width, and a 32-bit frame carries an
// alpha byte the decoder drops.
#test
{
    var wide: AviCase
    wide.width  = 3
    wide.height = 1
    wide.addFrame([0'u8, 0, 255, 0, 255, 0, 255, 0, 0, 0, 0, 0])

    let wideBytes = wide.build()
    var reader    = expect Reader.openMemory("padded.avi", wideBytes.toSlice())
    let row       = expect reader.decodeFrame(0)
    videoAssertColor(row.pixelColor(0, 0), 255, 0, 0, tolerance: 0)
    videoAssertColor(row.pixelColor(1, 0), 0, 255, 0, tolerance: 0)
    videoAssertColor(row.pixelColor(2, 0), 0, 0, 255, tolerance: 0)

    var deep: AviCase
    deep.width    = 2
    deep.height   = 1
    deep.bitCount = 32
    deep.addFrame([0'u8, 0, 255, 128, 0, 255, 0, 255])

    let deepBytes = deep.build()
    var alpha     = expect Reader.openMemory("deep.avi", deepBytes.toSlice())
    let opaque    = expect alpha.decodeFrame(0)
    videoAssertColor(opaque.pixelColor(0, 0), 255, 0, 0, tolerance: 0)
    videoAssertColor(opaque.pixelColor(1, 0), 0, 255, 0, tolerance: 0)
}

// The index is a shortcut, not the only way in: a file without one, and a file whose index
// counts from the start of the file rather than from the frame list, both read the same.
#test
{
    var walked: AviCase
    walked.hasIndex = false
    walked.addFrame(AviBottomUpFrame)
    walked.addFrame(AviBottomUpFrame)

    let walkedBytes = walked.build()
    var reader      = expect Reader.openMemory("walked.avi", walkedBytes.toSlice())
    @assert(reader.frameCount() == 2)
    aviAssertCornerFrame(expect reader.decodeFrame(1))

    var absolute: AviCase
    absolute.isIndexAbsolute = true
    absolute.addFrame(AviBottomUpFrame)
    absolute.addFrame(AviBottomUpFrame)

    let absoluteBytes = absolute.build()
    var addressed     = expect Reader.openMemory("absolute.avi", absoluteBytes.toSlice())
    @assert(addressed.frameCount() == 2)
    aviAssertCornerFrame(expect addressed.decodeFrame(1))

    // An OpenDML file groups its frames into `rec ` lists, so walking one has to step into them
    // instead of over them.
    var grouped: AviCase
    grouped.hasIndex  = false
    grouped.isGrouped = true
    grouped.addFrame(AviBottomUpFrame)
    grouped.addFrame(AviBottomUpFrame)

    let groupedBytes = grouped.build()
    var records      = expect Reader.openMemory("grouped.avi", groupedBytes.toSlice())
    @assert(records.frameCount() == 2)
    aviAssertCornerFrame(expect records.decodeFrame(1))
}

// The codec of an uncompressed stream is spelled as a zero as often as it is spelled as a name,
// and both say the same thing.
#test
{
    var raw: AviCase
    raw.compression = ""
    raw.addFrame(AviBottomUpFrame)

    let bytes  = raw.build()
    var reader = expect Reader.openMemory("raw.avi", bytes.toSlice())
    @assert(reader.frameCount() == 1)
    aviAssertCornerFrame(expect reader.decodeFrame(0))
}

// A frame that repeats the picture before it is stored as a chunk with no payload, and reading
// it must produce that picture whichever order the frames are asked for.
#test
{
    var repeated: AviCase
    repeated.addFrame(AviBottomUpFrame)
    repeated.addRepeatedFrame()
    repeated.addRepeatedFrame()

    let bytes  = repeated.build()
    var reader = expect Reader.openMemory("repeated.avi", bytes.toSlice())
    @assert(reader.frameCount() == 3)
    aviAssertCornerFrame(expect reader.decodeFrame(2))
    aviAssertCornerFrame(expect reader.decodeFrame(1))
    aviAssertCornerFrame(expect reader.decodeFrame(0))

    // A stream whose first frame carries no picture has nothing to repeat.
    var headless: AviCase
    headless.addRepeatedFrame()
    let headlessBytes = headless.build()
    var empty         = expect Reader.openMemory("headless.avi", headlessBytes.toSlice())
    discard catch empty.decodeFrame(0) as noPicture
    @assert(noPicture is InvalidFormatError)
}

// A stream written to a file reads back through the file-backed sink, which is the path where
// the header totals are rewritten in place rather than in memory.
#test
{
    let fileName = videoTempPath("avi-roundtrip", "avi")
    defer discard catch File.delete(fileName)

    let rate = expect FrameRate.create(12, 1)
    var clip = expect Clip.create(8, 8, rate)
    expect clip.addFrame(videoGrayImage(8, 8, 32))
    expect clip.addFrame(videoGrayImage(8, 8, 128))
    expect clip.addFrame(videoGrayImage(8, 8, 224))
    expect clip.save(fileName)

    var reader = expect Reader.open(fileName)
    @assert(reader.sourcePath() == fileName.toString())
    @assert(reader.frameCount() == 3 and reader.width() == 8 and reader.height() == 8)

    var frame: Image
    expect reader.decodeFrameInto(&frame, 2)
    videoAssertColor(frame.pixelColor(4, 4), 224, 224, 224, tolerance: 10)

    // Decoding into the same image reuses its storage instead of allocating another frame.
    let storage = frame.pixels.buffer
    expect reader.decodeFrameInto(&frame, 0)
    videoAssertColor(frame.pixelColor(4, 4), 32, 32, 32, tolerance: 10)
    @assert(frame.pixels.buffer == storage)

    reader.close()
    @assert(!reader.isOpen())
}

#test
{
    discard catch Reader.openMemory("bad.avi", "not a riff file at all") as notRiff
    discard catch Reader.openMemory("bad.avi", "RIFFsizeWAVEfmt ") as notAvi
    @assert(notRiff is InvalidFormatError)
    @assert(notAvi is InvalidFormatError)

    var silent: AviCase
    silent.streamKind = "auds"
    silent.addFrame(AviBottomUpFrame)
    let silentBytes = silent.build()
    discard catch Reader.openMemory("silent.avi", silentBytes.toSlice()) as noVideo
    @assert(noVideo is UnsupportedFormatError)

    var exotic: AviCase
    exotic.compression = "XVID"
    exotic.addFrame(AviBottomUpFrame)
    let exoticBytes = exotic.build()
    discard catch Reader.openMemory("exotic.avi", exoticBytes.toSlice()) as noCodec
    @assert(noCodec is UnsupportedFormatError)

    var indexed: AviCase
    indexed.bitCount = 8
    indexed.addFrame(AviBottomUpFrame)
    let indexedBytes = indexed.build()
    discard catch Reader.openMemory("indexed.avi", indexedBytes.toSlice()) as noDepth
    @assert(noDepth is UnsupportedFormatError)

    var barren: AviCase
    let barrenBytes = barren.build()
    discard catch Reader.openMemory("barren.avi", barrenBytes.toSlice()) as noFrame
    @assert(noFrame is InvalidFormatError)
}
