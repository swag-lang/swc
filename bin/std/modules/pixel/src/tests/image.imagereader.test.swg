#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

#test
{
    var reader = expect ImageReader.load(getTestDataPath("imageset-restore.apng"))
    let pixels = expect File.readAllBytes(getTestDataPath("imageset-restore.apng.rgba"))
    Swag.assert(reader.info.frames.count == 4 and reader.info.frames[2].disposal == .Previous)
    for index in [0'u32, 1, 2, 3, 1, 3]
    {
        let image = expect reader.read(index)
        Swag.assert(Memory.compare(image.pixels.buffer, pixels.buffer! + cast(u64) index * 64, 64) == 0)
    }

    var poster = expect ImageReader.load(getTestDataPath("imageset-poster.apng"))
    Swag.assert(poster.info.frames.count == 2)
    let animated = expect poster.read(0)
    let still    = expect Image.load(getTestDataPath("imageset-poster.apng"))
    Swag.assert(still.pixelColor(0, 0).r == 255 and animated.pixelColor(0, 0).a == 0)
}

// Metadata remains optional for both still PNG and WebP animation readers.
#test
{
    var source = Image.create(2, 2, .RGBA8)
    source.fill(Argb.White)
    var metadata: ImageMetadata
    metadata.signature = 1
    metadata.tag       = "Exif"
    const ExifBytes: [26] u8 = ['I', 'I', 42, 0, 8, 0, 0, 0, 1, 0, 18, 1, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0]
    metadata.value.add(ExifBytes)
    source.metadata.add(metadata)
    let encoded = expect source.encode("metadata.png")
    let decoded = expect Image.decode("metadata.png", encoded.toSlice())
    Swag.assert(decoded.metadata.count == 1 and decoded.metadata[0].signature == 1)
    let properties = expect Exif.decode(decoded.metadata[0].toSlice())
    Swag.assert(properties.count == 1 and properties[0].value == "6")

    var webp = expect File.readAllBytes(getTestDataPath("imageset-animation.webp"))
    webp[20] |= 8
    webp.add("EXIF")
    webp.add([26'u8, 0, 0, 0])
    webp.add(ExifBytes)
    (webp.buffer! + 4)[as u32] = cast(u32) webp.count - 8
    for enabled in [false, true]
    {
        var reader = expect ImageReader.decode("metadata.webp", webp.toSlice(), {decodeMetadata: enabled})
        let frame  = expect reader.read(2)
        Swag.assert(frame.metadata.count == (enabled ? 1'u64 : 0'u64))
        if enabled do
            Swag.assert(frame.metadata[0].isTag("Exif") and frame.metadata[0].value.count == 26)
    }
}

// Cyclic page chains and oversized indexed containers fail during indexing.
#test
{
    var tiff    = expect File.readAllBytes(getTestDataPath("imageset-pages-raw.tiff"))
    let first   = (tiff.buffer! + 4)[as u32]
    let entries = (tiff.buffer! + first)[as u16]
    (tiff.buffer! + first + 2 + cast(u64) entries * 12)[as u32] = first
    var reader = catch ImageReader.decode("cycle.tiff", tiff.toSlice()) as cycleError
    Swag.assert(cycleError != null)
    var dds = expect File.readAllBytes(getTestDataPath("imageset-array.dds"))
    (dds.buffer! + 140)[as u32] = Swag.U32.Max
    reader = catch ImageReader.decode("oversized.dds", dds.toSlice()) as arrayError
    Swag.assert(arrayError != null)
}

// Reference canvases use Pillow's raw decoders and source-over compositor, independently of Pixel.
#test
{
    for extension in ["webp", "apng", "gif"]
    {
        let name     = Format.toString("imageset-animation.%", extension)
        var reader   = expect ImageReader.load(getTestDataPath(name.toString()))
        let expected = expect File.readAllBytes(getTestDataPath(Format.toString("%.rgba", name.toString()).toString()))
        Swag.assert(reader.info.frames.count == 3)
        Swag.assert(reader.info.canvasWidth == 4 and reader.info.canvasHeight == 4)
        Swag.assert(reader.info.frames[0].durationSeconds == 0.04)
        Swag.assert(reader.info.frames[1].durationSeconds == 0.12)
        Swag.assert(reader.info.frames[2].durationSeconds == 0.08)
        Swag.assert(reader.info.loopCount == (extension == "gif" ? 2 : 1))
        for index in [0'u32, 1, 2, 2, 0, 2, 1, 0]
        {
            let frame = expect reader.read(index)
            Swag.assert(frame.width == 4 and frame.height == 4 and frame.pixelFormat == .RGBA8)
            Swag.assert(Memory.compare(frame.pixels.buffer, expected.buffer! + cast(u64) index * 64, 64) == 0)
        }

        let retained = expect reader.read(2)
        reader.close()
        reader.close()
        Swag.assert(!reader.isOpen() and retained.isValid())
        var invalid = catch reader.read(0) as error
        Swag.assert(error != null)
    }
}

#test
{
    for compression in ["raw", "packbits", "tiff-lzw"]
    {
        var reader = expect ImageReader.load(getTestDataPath(Format.toString("imageset-pages-%.tiff", compression).toString()))
        Swag.assert(reader.info.frames.count == 3)
        Swag.assert(reader.info.frames[0].kind == .Page)
        for index in [2'u32, 0, 1]
        {
            let image  = expect reader.read(index)
            let width  = index == 0 ? 2 : (index == 1 ? 4 : 1)
            let height = index == 0 ? 3 : (index == 1 ? 2 : 1)
            Swag.assert(image.width == width and image.height == height)
            let expected: [3] u32 = [0xFFFF0000, 0xFF008000, 0xFF0000FF]
            Swag.assert(image.pixelColor(0, 0).argb == expected[index])
        }
    }

    var icons = expect ImageReader.load(getTestDataPath("imageset-icons.ico"))
    Swag.assert(icons.info.frames.count == 2 and icons.info.representativeIndex == 1)
    let small = expect icons.read(0)
    let large = expect icons.read(1)
    Swag.assert(small.width == 2 and large.width == 4)
    Swag.assert(small.pixelColor(0, 0).argb == 0xFFFF0000 and large.pixelColor(0, 0).argb == 0xFF0000FF)
}

#test
{
    for extension in ["dds", "ktx2"]
    {
        for variant in ["array", "cube", "volume"]
        {
            var reader = expect ImageReader.load(getTestDataPath(Format.toString("imageset-%.%", variant, extension).toString()))
            let count  = variant == "array" ? 4'u64 : (variant == "cube" ? 12'u64 : 3'u64)
            Swag.assert(reader.info.frames.count == count)
            for index in range(0'u64, count).reversed()
            {
                let info  = &reader.info.frames[index]
                let image = expect reader.read(cast(u32) index)
                Swag.assert(info.kind == .Texture and image.width == cast(s32) (2 >> info.level))
                Swag.assert(image.pixelColor(0, 0).r == 20 + index * 10)
                Swag.assert(image.pixelColor(0, 0).g == 40 and image.pixelColor(0, 0).b == 60)
            }
        }
    }

    var compressed = expect ImageReader.load(getTestDataPath("imageset-zlib.ktx2"))
    Swag.assert(compressed.info.frames.count == 4)
    let last = expect compressed.read(3)
    Swag.assert(last.width == 1 and last.pixelColor(0, 0).r == 50)
}

#test
{
    var reader = expect ImageReader.load(getTestDataPath("imageset-parts.exr"))
    Swag.assert(reader.info.frames.count == 2)
    Swag.assert(reader.info.frames[1].name == "Part 2")
    for index in [1'u32, 0, 1]
    {
        let image = expect reader.read(index)
        Swag.assert(image.width == (index ? 3 : 2) and image.pixelFormat == .RGBF32)
        let samples = cast(const [*] f32) image.pixels.buffer!
        Swag.assert(samples[0] == 1.0 + index and samples[1] == 0.5 and samples[2] == 0.25)
    }
}

#test
{
    for compression in 4
    {
        var reader = expect ImageReader.load(getTestDataPath(Format.toString("imageset-layers-%.psd", compression).toString()))
        Swag.assert(reader.info.frames.count == 3 and reader.info.representativeIndex == 0)
        Swag.assert(reader.info.frames[1].kind == .Layer and reader.info.frames[2].name == "Layer 2")
        let composite = expect reader.read(0)
        let second    = expect reader.read(2)
        let first     = expect reader.read(1)
        Swag.assert(composite.width == 4 and composite.pixelColor(0, 0).argb == 0xFFFF0000)
        Swag.assert(first.width == 2 and first.pixelColor(0, 0).argb == 0xFFFF0000)
        Swag.assert(second.width == 2 and second.pixelColor(0, 0).argb == 0x8000FF00)
    }
}

// The same reader handles single images, metadata-only reads, ownership, and limits.
#test
{
    var source = Image.create(2, 2, .RGBA8)
    source.fill(Argb.Red)
    let encoded = expect source.encode("still.bmp")
    var reader  = expect ImageReader.decode("still.bmp", nnBytes(encoded.toSlice()))
    Swag.assert(reader.info.frames.count == 1)
    let decoded = expect reader.read(0)
    Swag.assert(decoded.pixelColor(0, 0).argb == 0xFFFF0000)
    var missing = catch reader.read(1) as rangeError
    Swag.assert(rangeError != null)

    for name in ["imageset-animation.webp", "imageset-animation.apng", "imageset-animation.gif", "imageset-pages-raw.tiff", "imageset-icons.ico", "imageset-array.dds", "imageset-array.ktx2", "imageset-parts.exr", "imageset-layers-0.psd"]
    {
        var probe = expect ImageReader.load(getTestDataPath(name), {decodePixels: false})
        let image = expect probe.read(0)
        Swag.assert(image.width > 0 and image.height > 0 and image.pixels.count == 0)
        var limited = catch ImageReader.load(getTestDataPath(name), {maxFrames: 1}) as frameError
        Swag.assert(frameError != null)
        limited = catch ImageReader.load(getTestDataPath(name), {maxPixels: 1}) as pixelError
        Swag.assert(pixelError != null)
        limited = catch ImageReader.load(getTestDataPath(name), {maxInputBytes: 4}) as inputError
        Swag.assert(inputError != null)
        let bytes = expect File.readAllBytes(getTestDataPath(name))
        for length in [0'u64, 4, 12]
        {
            limited = catch ImageReader.decode(name, Swag.makeSlice(bytes.buffer!, length)) as truncatedError
            Swag.assert(truncatedError != null)
        }
    }
}
