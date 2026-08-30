#global if #command == Swag.CompilerCommand.Test

using Swag, Core

const TGA_TYPE_MAP      = 1'u8
const TGA_TYPE_RGB      = 2'u8
const TGA_TYPE_MONO     = 3'u8
const TGA_TYPE_RLE_MAP  = 9'u8
const TGA_TYPE_RLE_RGB  = 10'u8
const TGA_TYPE_RLE_MONO = 11'u8

const TGA_DESC_RIGHT = 0x10'u8
const TGA_DESC_TOP   = 0x20'u8

#[Swag.Pack(1)]
struct TgaH
{
    idLength:       u8
    colorMapType:   u8
    imageTypeCode:  u8
    colorMapFirst:  u16
    colorMapLength: u16
    colorMapBpp:    u8
    originX:        u16
    originY:        u16
    width:          u16
    height:         u16
    bitsPerPixel:   u8
    descriptorByte: u8
}

func addTgaImageHeader(cb: *ConcatBuffer, imageType, bpp, descriptor: u8, width, height: u16)
{
    var h: TgaH
    h.imageTypeCode  = imageType
    h.width          = width
    h.height         = height
    h.bitsPerPixel   = bpp
    h.descriptorByte = descriptor
    cb.addStruct(h)
}

func addTgaPaletteColor(cb: *ConcatBuffer, b, g, r: u8)
{
    cb.addNative(b)
    cb.addNative(g)
    cb.addNative(r)
}

// Decode every 16-bit word plus an odd tail, with unaligned buffers and sentinels.
// Both directions and alpha modes must match the scalar expansion exactly.
#test
{
    const Pixels = 65536 + 1
    var source:   Array'u8
    var actual:   Array'u8
    var expected: Array'u8
    source.resize(1 + Pixels * 2)
    actual.resize(3 + Pixels * 4 + 1)
    expected.resize(actual.count)

    for alphaMode in 2
    {
        for i in actual.count
        {
            actual[i]   = 0xA5
            expected[i] = 0xA5
        }

        let alphaFromBit = alphaMode != 0
        for i in Pixels
        {
            let value = cast(u16) (i & 0xFFFF)
            source[1 + i * 2]       = cast(u8) (value & 0xFF)
            source[1 + i * 2 + 1]   = cast(u8) (value >> 8)
            expected[3 + i * 4]     = Tga.expand5(value & 31)
            expected[3 + i * 4 + 1] = Tga.expand5((value >> 5) & 31)
            expected[3 + i * 4 + 2] = Tga.expand5((value >> 10) & 31)
            expected[3 + i * 4 + 3] = alphaFromBit ? (value & 0x8000 ? 255 : 0) : 255
        }

        Tga.decodeTga16Row(source.buffer! + 1, actual.buffer! + 3, Pixels, alphaFromBit)
        for i in actual.count do
            Swag.assert(actual[i] == expected[i])

        for i in actual.count
        {
            actual[i]   = 0xA5
            expected[i] = 0xA5
        }

        for i in Pixels
        {
            let value = cast(u16) ((Pixels - i - 1) & 0xFFFF)
            expected[3 + i * 4]     = Tga.expand5(value & 31)
            expected[3 + i * 4 + 1] = Tga.expand5((value >> 5) & 31)
            expected[3 + i * 4 + 2] = Tga.expand5((value >> 10) & 31)
            expected[3 + i * 4 + 3] = alphaFromBit ? (value & 0x8000 ? 255 : 0) : 255
        }

        Tga.decodeTga16RowReversed(source.buffer! + 1, actual.buffer! + 3, Pixels, alphaFromBit)
        for i in actual.count do
            Swag.assert(actual[i] == expected[i])
    }

    actual.resize(3 + Pixels * 3 + 1)
    expected.resize(actual.count)
    for i in actual.count
    {
        actual[i]   = 0xA5
        expected[i] = 0xA5
    }

    for i in Pixels
    {
        let value = cast(u16) ((Pixels - i - 1) & 0xFFFF)
        expected[3 + i * 3]     = Tga.expand5(value & 31)
        expected[3 + i * 3 + 1] = Tga.expand5((value >> 5) & 31)
        expected[3 + i * 3 + 2] = Tga.expand5((value >> 10) & 31)
    }

    Tga.decodeTga15RowReversed(source.buffer! + 1, actual.buffer! + 3, Pixels)
    for i in actual.count do
        Swag.assert(actual[i] == expected[i])
}

// Fill unaligned packed rows across every SIMD tail width without touching sentinels.
#test
{
    for bytesPerPixel in [3'u64, 4'u64]
    {
        for width in 20'u64
        {
            let pixelCount = width + 1
            var source:   Array'u8
            var actual:   Array'u8
            var expected: Array'u8
            source.resize(1 + bytesPerPixel + 1)
            actual.resize(3 + pixelCount * bytesPerPixel + 1)
            expected.resize(actual.count)
            for i in source.count do
                source[i] = cast(u8) ((i * 43 + 17) & 0xFF)
            for i in actual.count
            {
                actual[i]   = 0xA5
                expected[i] = 0xA5
            }

            for x in pixelCount
            {
                for channel in bytesPerPixel do
                    expected[3 + x * bytesPerPixel + channel] = source[1 + channel]
            }

            if bytesPerPixel == 3 do
                PackedPixel.fillBgr24Row(source.buffer! + 1, actual.buffer! + 3, pixelCount)
            else do
                PackedPixel.fillBgra32Row(source.buffer! + 1, actual.buffer! + 3, pixelCount)
            for i in actual.count do
                Swag.assert(actual[i] == expected[i])
        }
    }
}

// Reverse unaligned packed rows across every SIMD tail width without touching sentinels.
#test
{
    for bytesPerPixel in [3'u64, 4'u64]
    {
        for width in 20'u64
        {
            let pixelCount = width + 1
            var source:   Array'u8
            var actual:   Array'u8
            var expected: Array'u8
            source.resize(1 + pixelCount * bytesPerPixel + 1)
            actual.resize(3 + pixelCount * bytesPerPixel + 1)
            expected.resize(actual.count)
            for i in source.count do
                source[i] = cast(u8) ((i * 37 + 11) & 0xFF)
            for i in actual.count
            {
                actual[i]   = 0xA5
                expected[i] = 0xA5
            }

            for x in pixelCount
            {
                let sourceOffset = 1 + (pixelCount - x - 1) * bytesPerPixel
                let targetOffset = 3 + x * bytesPerPixel
                for channel in bytesPerPixel do
                    expected[targetOffset + channel] = source[sourceOffset + channel]
            }

            if bytesPerPixel == 3 do
                PackedPixel.reverseBgr24Row(source.buffer! + 1, actual.buffer! + 3, pixelCount)
            else do
                PackedPixel.reverseBgra32Row(source.buffer! + 1, actual.buffer! + 3, pixelCount)
            for i in actual.count do
                Swag.assert(actual[i] == expected[i])
        }
    }
}

// Find every possible first mismatch around the four-pixel SIMD boundary.
#test
{
    const Candidates = 130'u64
    var pixel:      Array'u8
    var candidates: Array'u8
    pixel.resize(5)
    candidates.resize(1 + Candidates * 4 + 1)
    for channel in 4 do
        pixel[1 + channel] = cast(u8) (channel * 53 + 17)

    for mismatch in Candidates + 1
    {
        for candidate in Candidates
        {
            for channel in 4 do
                candidates[1 + candidate * 4 + channel] = pixel[1 + channel]
        }

        if mismatch < Candidates do
            candidates[1 + mismatch * 4 + 2] ^= 0xFF
        Swag.assert(PackedPixel.countSame32(pixel.buffer! + 1, candidates.buffer! + 1, Candidates) == mismatch)
    }
}

// Decode top-origin raw 15-bit rows through the shared BGR555 vector kernel,
// including a full vector and an odd tail on each row.
#test
{
    const Width  = 17'u16
    const Height = 2'u16
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 15, TGA_DESC_TOP, Width, Height)
    for i in cast(u64) Width * Height do
        cb.addNative(cast(u16) ((i * 1907 + 123) & 0x7FFF))

    let img = expect Image.decode("memory.tga", nnBytes(cb.toSlice()), {})
    Swag.assert(img.width == Width and img.height == Height and img.pixelFormat == .BGR8)
    for i in cast(u64) Width * Height
    {
        let sourceY = i / Width
        let x       = i % Width
        let targetY = Height - sourceY - 1
        let offset  = (targetY * Width + x) * 3
        let value   = cast(u32) ((i * 1907 + 123) & 0x7FFF)
        Swag.assert(img.pixels.buffer![offset] == Tga.expand5(value & 31))
        Swag.assert(img.pixels.buffer![offset + 1] == Tga.expand5((value >> 5) & 31))
        Swag.assert(img.pixels.buffer![offset + 2] == Tga.expand5((value >> 10) & 31))
    }
}

// Decode right-origin packed rows through a full vector and an odd tail on each row.
#test
{
    const Width  = 17'u16
    const Height = 2'u16
    {
        var cb: ConcatBuffer
        addTgaImageHeader(&cb, TGA_TYPE_RGB, 15, TGA_DESC_TOP | TGA_DESC_RIGHT, Width, Height)
        for i in cast(u64) Width * Height do
            cb.addNative(cast(u16) ((i * 1907 + 123) & 0x7FFF))

        let img = expect Image.decode("memory.tga", nnBytes(cb.toSlice()), {})
        Swag.assert(img.width == Width and img.height == Height and img.pixelFormat == .BGR8)
        for i in cast(u64) Width * Height
        {
            let sourceY = i / Width
            let sourceX = i % Width
            let targetY = Height - sourceY - 1
            let targetX = Width - sourceX - 1
            let offset  = (targetY * Width + targetX) * 3
            let value   = cast(u32) ((i * 1907 + 123) & 0x7FFF)
            Swag.assert(img.pixels.buffer![offset] == Tga.expand5(value & 31))
            Swag.assert(img.pixels.buffer![offset + 1] == Tga.expand5((value >> 5) & 31))
            Swag.assert(img.pixels.buffer![offset + 2] == Tga.expand5((value >> 10) & 31))
        }
    }

    {
        var cb: ConcatBuffer
        addTgaImageHeader(&cb, TGA_TYPE_RGB, 16, TGA_DESC_TOP | TGA_DESC_RIGHT | 1, Width, Height)
        for i in cast(u64) Width * Height do
            cb.addNative(cast(u16) (i * 1907 + 123))

        let img = expect Image.decode("memory.tga", nnBytes(cb.toSlice()), {})
        Swag.assert(img.width == Width and img.height == Height and img.pixelFormat == .BGRA8)
        for i in cast(u64) Width * Height
        {
            let sourceY = i / Width
            let sourceX = i % Width
            let targetY = Height - sourceY - 1
            let targetX = Width - sourceX - 1
            let offset  = (targetY * Width + targetX) * 4
            let value   = cast(u32) ((i * 1907 + 123) & 0xFFFF)
            Swag.assert(img.pixels.buffer![offset] == Tga.expand5(value & 31))
            Swag.assert(img.pixels.buffer![offset + 1] == Tga.expand5((value >> 5) & 31))
            Swag.assert(img.pixels.buffer![offset + 2] == Tga.expand5((value >> 10) & 31))
            Swag.assert(img.pixels.buffer![offset + 3] == (value & 0x8000 ? 255'u8 : 0'u8))
        }
    }
}

// Decode raw BGR/BGRA rows through the direct-copy and reversed SIMD paths.
#test
{
    const Width  = 17'u16
    const Height = 2'u16
    for bpp in [24'u8, 32'u8]
    {
        let bytesPerPixel = cast(u64) (bpp / 8)
        for rightMode in 2
        {
            var cb: ConcatBuffer
            addTgaImageHeader(&cb, TGA_TYPE_RGB, bpp, TGA_DESC_TOP | (rightMode ? TGA_DESC_RIGHT : 0), Width, Height)
            for pixel in cast(u64) Width * Height
            {
                for channel in bytesPerPixel do
                    cb.addNative(cast(u8) ((pixel * 29 + channel * 71 + 13) & 0xFF))
            }

            let img = expect Image.decode("memory.tga", nnBytes(cb.toSlice()), {})
            Swag.assert(img.width == Width and img.height == Height)
            Swag.assert(img.pixelFormat == (bpp == 24 ? .BGR8 : .BGRA8))
            for pixel in cast(u64) Width * Height
            {
                let sourceY = pixel / Width
                let sourceX = pixel % Width
                let targetY = Height - sourceY - 1
                let targetX = rightMode ? Width - sourceX - 1 : sourceX
                let offset  = (targetY * Width + targetX) * bytesPerPixel
                for channel in bytesPerPixel do
                    Swag.assert(img.pixels.buffer![offset + channel] == cast(u8) ((pixel * 29 + channel * 71 + 13) & 0xFF))
            }
        }
    }
}

// Decoder and encoder registries recognise TGA files.
#test
{
    Swag.assert(Image.canLoad("in.tga"))
    Swag.assert(Image.canSave("out.tga"))
}

// Decode a raw 2x2 24-bit TGA with the default bottom-left origin.
#test
{
    let path = makeTempTgaPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 24'u8, 0'u8, 2'u16, 2'u16)
    cb.addNative(10'u8)
    cb.addNative(20'u8)
    cb.addNative(30'u8)
    cb.addNative(40'u8)
    cb.addNative(50'u8)
    cb.addNative(60'u8)
    cb.addNative(70'u8)
    cb.addNative(80'u8)
    cb.addNative(90'u8)
    cb.addNative(100'u8)
    cb.addNative(110'u8)
    cb.addNative(120'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.width == 2)
    Swag.assert(img.height == 2)
    Swag.assert(img.pixelFormat == .BGR8)
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 10'u8)
    Swag.assert(img.pixels.buffer[1] == 20'u8)
    Swag.assert(img.pixels.buffer[2] == 30'u8)
    Swag.assert(img.pixels.buffer[9] == 100'u8)
    Swag.assert(img.pixels.buffer[10] == 110'u8)
    Swag.assert(img.pixels.buffer[11] == 120'u8)
}

// Load larger RGB/RGBA fixtures copied from the historical pixel test data.
#test
{
    let rgb = expect Image.load(getTestDataPath("rgb.tga"))
    Swag.assert(rgb.isValid())
    Swag.assert(rgb.width == 660)
    Swag.assert(rgb.height == 441)
    Swag.assert(rgb.pixelFormat == .BGR8)
    Swag.assert(rgb.pixels.count == 873180)
    Swag.assert(rgb.pixels.buffer != null)
    Swag.assert(rgb.pixels.buffer[0] == 201'u8)
    Swag.assert(rgb.pixels.buffer[1] == 205'u8)
    Swag.assert(rgb.pixels.buffer[2] == 194'u8)

    let rgba = expect Image.load(getTestDataPath("rgba.tga"))
    Swag.assert(rgba.isValid())
    Swag.assert(rgba.width == 660)
    Swag.assert(rgba.height == 441)
    Swag.assert(rgba.pixelFormat == .BGRA8)
    Swag.assert(rgba.pixels.count == 1164240)
    Swag.assert(rgba.pixels.buffer != null)
    Swag.assert(rgba.pixels.buffer[0] == 201'u8)
    Swag.assert(rgba.pixels.buffer[1] == 205'u8)
    Swag.assert(rgba.pixels.buffer[2] == 194'u8)
    Swag.assert(rgba.pixels.buffer[3] == 255'u8)
}

// Load RLE RGB/RGBA fixtures copied from the historical pixel test data.
#test
{
    let rle24 = expect Image.load(getTestDataPath("rle24.tga"))
    Swag.assert(rle24.isValid())
    Swag.assert(rle24.width == 660)
    Swag.assert(rle24.height == 441)
    Swag.assert(rle24.pixelFormat == .BGR8)
    Swag.assert(rle24.pixels.buffer != null)
    Swag.assert(rle24.pixels.buffer[0] == 201'u8)
    Swag.assert(rle24.pixels.buffer[1] == 205'u8)
    Swag.assert(rle24.pixels.buffer[2] == 194'u8)

    let rle32 = expect Image.load(getTestDataPath("rle32.tga"))
    Swag.assert(rle32.isValid())
    Swag.assert(rle32.width == 660)
    Swag.assert(rle32.height == 441)
    Swag.assert(rle32.pixelFormat == .BGRA8)
    Swag.assert(rle32.pixels.buffer != null)
    Swag.assert(rle32.pixels.buffer[0] == 201'u8)
    Swag.assert(rle32.pixels.buffer[1] == 205'u8)
    Swag.assert(rle32.pixels.buffer[2] == 194'u8)
    Swag.assert(rle32.pixels.buffer[3] == 255'u8)
}

// Decode skips the optional image ID field before pixel data.
#test
{
    let path = makeTempTgaPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var h:  TgaH
    h.idLength      = 3'u8
    h.imageTypeCode = TGA_TYPE_RGB
    h.width         = 1'u16
    h.height        = 1'u16
    h.bitsPerPixel  = 24'u8
    cb.addStruct(h)
    cb.addNative(73'u8)
    cb.addNative(68'u8)
    cb.addNative(33'u8)
    cb.addNative(8'u8)
    cb.addNative(9'u8)
    cb.addNative(10'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 8'u8)
    Swag.assert(img.pixels.buffer[1] == 9'u8)
    Swag.assert(img.pixels.buffer[2] == 10'u8)
}

// Decode a top-origin TGA into the module's bottom-up image buffer.
#test
{
    let path = makeTempTgaPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 24'u8, TGA_DESC_TOP, 2'u16, 2'u16)
    cb.addNative(1'u8)
    cb.addNative(2'u8)
    cb.addNative(3'u8)
    cb.addNative(4'u8)
    cb.addNative(5'u8)
    cb.addNative(6'u8)
    cb.addNative(7'u8)
    cb.addNative(8'u8)
    cb.addNative(9'u8)
    cb.addNative(10'u8)
    cb.addNative(11'u8)
    cb.addNative(12'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 7'u8)
    Swag.assert(img.pixels.buffer[1] == 8'u8)
    Swag.assert(img.pixels.buffer[2] == 9'u8)
    Swag.assert(img.pixels.buffer[6] == 1'u8)
    Swag.assert(img.pixels.buffer[7] == 2'u8)
    Swag.assert(img.pixels.buffer[8] == 3'u8)
}

// Decode a right-origin TGA by reversing pixels within the row.
#test
{
    let path = makeTempTgaPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 24'u8, TGA_DESC_RIGHT, 2'u16, 1'u16)
    cb.addNative(1'u8)
    cb.addNative(2'u8)
    cb.addNative(3'u8)
    cb.addNative(4'u8)
    cb.addNative(5'u8)
    cb.addNative(6'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 4'u8)
    Swag.assert(img.pixels.buffer[1] == 5'u8)
    Swag.assert(img.pixels.buffer[2] == 6'u8)
    Swag.assert(img.pixels.buffer[3] == 1'u8)
    Swag.assert(img.pixels.buffer[4] == 2'u8)
    Swag.assert(img.pixels.buffer[5] == 3'u8)
}

// Decode 16-bit true-color TGA pixels as BGRA8.
#test
{
    let path = makeTempTgaPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 16'u8, 1'u8, 2'u16, 1'u16)
    cb.addNative(0xFC00'u16)
    cb.addNative(0x03E0'u16)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixelFormat == .BGRA8)
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 0'u8)
    Swag.assert(img.pixels.buffer[1] == 0'u8)
    Swag.assert(img.pixels.buffer[2] == 255'u8)
    Swag.assert(img.pixels.buffer[3] == 255'u8)
    Swag.assert(img.pixels.buffer[4] == 0'u8)
    Swag.assert(img.pixels.buffer[5] == 255'u8)
    Swag.assert(img.pixels.buffer[6] == 0'u8)
    Swag.assert(img.pixels.buffer[7] == 0'u8)
}

// Decode 8-bit grayscale TGA as BGR8.
#test
{
    let path = makeTempTgaPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_MONO, 8'u8, 0'u8, 3'u16, 1'u16)
    cb.addNative(5'u8)
    cb.addNative(10'u8)
    cb.addNative(15'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixelFormat == .BGR8)
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 5'u8)
    Swag.assert(img.pixels.buffer[1] == 5'u8)
    Swag.assert(img.pixels.buffer[2] == 5'u8)
    Swag.assert(img.pixels.buffer[6] == 15'u8)
    Swag.assert(img.pixels.buffer[7] == 15'u8)
    Swag.assert(img.pixels.buffer[8] == 15'u8)
}

// Decode an 8-bit indexed TGA with a non-zero palette base index.
#test
{
    let path = makeTempTgaPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var h:  TgaH
    h.colorMapType   = 1'u8
    h.imageTypeCode  = TGA_TYPE_MAP
    h.colorMapFirst  = 2'u16
    h.colorMapLength = 2'u16
    h.colorMapBpp    = 24'u8
    h.width          = 2'u16
    h.height         = 1'u16
    h.bitsPerPixel   = 8'u8
    cb.addStruct(h)
    addTgaPaletteColor(&cb, 10, 20, 30)
    addTgaPaletteColor(&cb, 40, 50, 60)
    cb.addNative(2'u8)
    cb.addNative(3'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixelFormat == .BGR8)
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 10'u8)
    Swag.assert(img.pixels.buffer[1] == 20'u8)
    Swag.assert(img.pixels.buffer[2] == 30'u8)
    Swag.assert(img.pixels.buffer[3] == 40'u8)
    Swag.assert(img.pixels.buffer[4] == 50'u8)
    Swag.assert(img.pixels.buffer[5] == 60'u8)
}

// Decode indexed TGA with 32-bit palette entries and preserve alpha.
#test
{
    let path = makeTempTgaPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var h:  TgaH
    h.colorMapType   = 1'u8
    h.imageTypeCode  = TGA_TYPE_MAP
    h.colorMapLength = 1'u16
    h.colorMapBpp    = 32'u8
    h.width          = 1'u16
    h.height         = 1'u16
    h.bitsPerPixel   = 8'u8
    cb.addStruct(h)
    cb.addNative(3'u8)
    cb.addNative(4'u8)
    cb.addNative(5'u8)
    cb.addNative(6'u8)
    cb.addNative(0'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixelFormat == .BGRA8)
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 3'u8)
    Swag.assert(img.pixels.buffer[1] == 4'u8)
    Swag.assert(img.pixels.buffer[2] == 5'u8)
    Swag.assert(img.pixels.buffer[3] == 6'u8)
}

// Decode RLE true-color packets.
#test
{
    let path = makeTempTgaPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RLE_RGB, 24'u8, 0'u8, 4'u16, 1'u16)
    cb.addNative(0x83'u8)
    cb.addNative(1'u8)
    cb.addNative(2'u8)
    cb.addNative(3'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 1'u8)
    Swag.assert(img.pixels.buffer[9] == 1'u8)
    Swag.assert(img.pixels.buffer[10] == 2'u8)
    Swag.assert(img.pixels.buffer[11] == 3'u8)
}

// Decode mixed raw and repeated packets that cross rows in every origin mode.
#test
{
    const Width  = 17'u16
    const Height = 3'u16
    const Pixels = cast(u64) Width * Height
    for bpp in [24'u8, 32'u8]
    {
        let bytesPerPixel = cast(u64) (bpp / 8)
        for topMode in 2
        {
            for rightMode in 2
            {
                let descriptor = (topMode ? TGA_DESC_TOP : 0) | (rightMode ? TGA_DESC_RIGHT : 0)
                var cb:       ConcatBuffer
                var expected: Array'u8
                expected.resize(Pixels * bytesPerPixel)
                addTgaImageHeader(&cb, TGA_TYPE_RLE_RGB, bpp, descriptor, Width, Height)

                cb.addNative(19'u8)
                for pixel in 20'u64
                {
                    for channel in bytesPerPixel
                    {
                        let value = cast(u8) ((pixel * 29 + channel * 71 + 13) & 0xFF)
                        cb.addNative(value)
                        expected[pixel * bytesPerPixel + channel] = value
                    }
                }

                cb.addNative(0x91'u8)
                for channel in bytesPerPixel do
                    cb.addNative(cast(u8) ((channel * 53 + 91) & 0xFF))
                for pixel in 18'u64
                {
                    for channel in bytesPerPixel do
                        expected[(20 + pixel) * bytesPerPixel + channel] = cast(u8) ((channel * 53 + 91) & 0xFF)
                }

                cb.addNative(12'u8)
                for packetPixel in 13'u64
                {
                    let pixel = 38 + packetPixel
                    for channel in bytesPerPixel
                    {
                        let value = cast(u8) ((pixel * 29 + channel * 71 + 13) & 0xFF)
                        cb.addNative(value)
                        expected[pixel * bytesPerPixel + channel] = value
                    }
                }

                let img = expect Image.decode("memory.tga", nnBytes(cb.toSlice()), {})
                Swag.assert(img.pixelFormat == (bpp == 24 ? .BGR8 : .BGRA8))
                for pixel in Pixels
                {
                    let sourceY = pixel / Width
                    let sourceX = pixel % Width
                    let targetY = topMode ? Height - sourceY - 1 : sourceY
                    let targetX = rightMode ? Width - sourceX - 1 : sourceX
                    let offset  = (targetY * Width + targetX) * bytesPerPixel
                    for channel in bytesPerPixel do
                        Swag.assert(img.pixels.buffer![offset + channel] == expected[pixel * bytesPerPixel + channel])
                }
            }
        }
    }
}

// Decode RLE color-mapped packets.
#test
{
    let path = makeTempTgaPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    var h:  TgaH
    h.colorMapType   = 1'u8
    h.imageTypeCode  = TGA_TYPE_RLE_MAP
    h.colorMapLength = 3'u16
    h.colorMapBpp    = 24'u8
    h.width          = 3'u16
    h.height         = 1'u16
    h.bitsPerPixel   = 8'u8
    cb.addStruct(h)
    addTgaPaletteColor(&cb, 1, 2, 3)
    addTgaPaletteColor(&cb, 4, 5, 6)
    addTgaPaletteColor(&cb, 7, 8, 9)
    cb.addNative(0x02'u8)
    cb.addNative(0'u8)
    cb.addNative(1'u8)
    cb.addNative(2'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 1'u8)
    Swag.assert(img.pixels.buffer[3] == 4'u8)
    Swag.assert(img.pixels.buffer[6] == 7'u8)
}

// Decode RLE grayscale packets.
#test
{
    let path = makeTempTgaPath()
    defer discard catch File.delete(path.toString())
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RLE_MONO, 8'u8, 0'u8, 3'u16, 1'u16)
    cb.addNative(0x02'u8)
    cb.addNative(9'u8)
    cb.addNative(10'u8)
    cb.addNative(11'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 9'u8)
    Swag.assert(img.pixels.buffer[3] == 10'u8)
    Swag.assert(img.pixels.buffer[6] == 11'u8)
}

// Decode metadata without allocating pixels.
#test
{
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 24'u8, 0'u8, 2'u16, 2'u16)

    var opts: DecodeOptions
    opts.decodePixels = false

    let img = expect Image.decode("meta.tga", nnBytes(cb.toSlice()), opts)
    Swag.assert(img.width == 2)
    Swag.assert(img.height == 2)
    Swag.assert(img.pixelFormat == .BGR8)
    Swag.assert(!img.isValid())
}

// Error: RLE packet cannot exceed the destination image.
#test
{
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RLE_RGB, 24'u8, 0'u8, 2'u16, 1'u16)
    cb.addNative(0x82'u8)
    cb.addNative(1'u8)
    cb.addNative(2'u8)
    cb.addNative(3'u8)

    var img: Image
    img = catch Image.decode("bad.tga", nnBytes(cb.toSlice()), {}) as err28
    Swag.assert(err28 != null)
}

// Error: color-mapped images require palette data.
#test
{
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_MAP, 8'u8, 0'u8, 1'u16, 1'u16)
    cb.addNative(0'u8)

    var img: Image
    img = catch Image.decode("bad.tga", nnBytes(cb.toSlice()), {}) as err29
    Swag.assert(err29 != null)
}

// Encode full SIMD blocks and tails from RGB/RGBA into TGA's BGR/BGRA order.
#test
{
    const Width  = 19
    const Height = 2
    for pixelFormat in [PixelFormat.RGB8, PixelFormat.RGBA8]
    {
        var src = Image.create(Width, Height, pixelFormat)
        for i in src.pixels.count do
            src.pixels.buffer![i] = cast(u8) ((i * 37 + 19) & 0xFF)

        let cb            = expect src.encode("memory.tga")
        let img           = expect Image.decode("memory.tga", nnBytes(cb.toSlice()), {})
        let bytesPerPixel = cast(u64) src.bytesPerPixel
        Swag.assert(cb.count() == #sizeof(TgaH) + src.pixels.count)
        Swag.assert(img.pixelFormat == (bytesPerPixel == 3 ? .BGR8 : .BGRA8))
        for pixel in cast(u64) Width * Height
        {
            let offset = pixel * bytesPerPixel
            Swag.assert(img.pixels.buffer![offset] == src.pixels.buffer![offset + 2])
            Swag.assert(img.pixels.buffer![offset + 1] == src.pixels.buffer![offset + 1])
            Swag.assert(img.pixels.buffer![offset + 2] == src.pixels.buffer![offset])
            if bytesPerPixel == 4 do
                Swag.assert(img.pixels.buffer![offset + 3] == src.pixels.buffer![offset + 3])
        }
    }
}

// Encode BGR8 and round-trip through the decoder.
#test
{
    let path = makeTempTgaPath()
    defer discard catch File.delete(path.toString())
    var src    = Image.create(2, 1, .BGR8)
    let srcBuf = src.pixels.buffer!
    srcBuf[0] = 1'u8
    srcBuf[1] = 2'u8
    srcBuf[2] = 3'u8
    srcBuf[3] = 4'u8
    srcBuf[4] = 5'u8
    srcBuf[5] = 6'u8

    let cb = expect src.encode("memory.tga")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 1'u8)
    Swag.assert(img.pixels.buffer[5] == 6'u8)
}

// Encode RGB8 by swapping R/B into the on-disk BGR order.
#test
{
    let path = makeTempTgaPath()
    defer discard catch File.delete(path.toString())
    var src    = Image.create(1, 1, .RGB8)
    let srcBuf = src.pixels.buffer!
    srcBuf[0] = 10'u8
    srcBuf[1] = 20'u8
    srcBuf[2] = 30'u8

    let cb = expect src.encode("memory.tga")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixelFormat == .BGR8)
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 30'u8)
    Swag.assert(img.pixels.buffer[1] == 20'u8)
    Swag.assert(img.pixels.buffer[2] == 10'u8)
}

// Encode RGBA8 with descriptor alpha bits and preserve alpha through round-trip.
#test
{
    let path = makeTempTgaPath()
    defer discard catch File.delete(path.toString())
    var src    = Image.create(1, 1, .RGBA8)
    let srcBuf = src.pixels.buffer!
    srcBuf[0] = 1'u8
    srcBuf[1] = 2'u8
    srcBuf[2] = 3'u8
    srcBuf[3] = 4'u8

    let cb = expect src.encode("memory.tga")
    cb.makeLinear()
    let bytes = nnBytes(cb.toSlice())
    Swag.assert(bytes != null)
    let h = cast(const *TgaH) bytes.buffer
    Swag.assert(h.imageTypeCode == TGA_TYPE_RGB)
    Swag.assert(h.bitsPerPixel == 32'u8)
    Swag.assert(h.descriptorByte == 8'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.assert(img.pixelFormat == .BGRA8)
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 3'u8)
    Swag.assert(img.pixels.buffer[1] == 2'u8)
    Swag.assert(img.pixels.buffer[2] == 1'u8)
    Swag.assert(img.pixels.buffer[3] == 4'u8)
}

// Split uniform input at the 128-pixel RLE limit in every channel order.
#test
{
    const Width = 257
    var options: Tga.EncodeOptions
    options.rle = true
    for pixelFormat in [PixelFormat.BGR8, PixelFormat.RGB8, PixelFormat.BGRA8, PixelFormat.RGBA8]
    {
        var src = Image.create(Width, 1, pixelFormat)
        Memory.set(src.pixels.buffer!, 73, src.pixels.count)

        var cb = expect src.encode("memory.tga", options)
        cb.makeLinear()
        let bytes         = nnBytes(cb.toSlice())
        let bytesPerPixel = cast(u64) src.bytesPerPixel
        Swag.assert(bytes.count == #sizeof(TgaH) + 3 * (1 + bytesPerPixel))
        Swag.assert(bytes[#sizeof(TgaH)] == 0xFF)
        Swag.assert(bytes[#sizeof(TgaH) + 1 + bytesPerPixel] == 0xFF)
        Swag.assert(bytes[#sizeof(TgaH) + 2 + 2 * bytesPerPixel] == 0)

        let img = expect Image.decode("memory.tga", bytes, {})
        for i in img.pixels.count do
            Swag.assert(img.pixels.buffer![i] == 73)
    }
}

// Encode a full 128-pixel literal packet and a tail in every channel order.
#test
{
    const Width = 131
    var options: Tga.EncodeOptions
    options.rle = true
    for pixelFormat in [PixelFormat.BGR8, PixelFormat.RGB8, PixelFormat.BGRA8, PixelFormat.RGBA8]
    {
        var src = Image.create(Width, 1, pixelFormat)
        for i in src.pixels.count do
            src.pixels.buffer![i] = cast(u8) ((i * 37 + 19) & 0xFF)

        var cb = expect src.encode("memory.tga", options)
        cb.makeLinear()
        let bytes         = nnBytes(cb.toSlice())
        let bytesPerPixel = cast(u64) src.bytesPerPixel
        Swag.assert(bytes[#sizeof(TgaH)] == 0x7F)
        Swag.assert(bytes[#sizeof(TgaH) + 1 + 128 * bytesPerPixel] == 2)

        let img = expect Image.decode("memory.tga", bytes, {})
        Swag.assert(img.pixelFormat == (pixelFormat == .BGR8 or pixelFormat == .RGB8 ? .BGR8 : .BGRA8))
        for pixel in cast(u64) Width
        {
            let offset = pixel * bytesPerPixel
            if pixelFormat == .BGR8 or pixelFormat == .BGRA8
            {
                for channel in bytesPerPixel do
                    Swag.assert(img.pixels.buffer![offset + channel] == src.pixels.buffer![offset + channel])
            }
            else
            {
                Swag.assert(img.pixels.buffer![offset] == src.pixels.buffer![offset + 2])
                Swag.assert(img.pixels.buffer![offset + 1] == src.pixels.buffer![offset + 1])
                Swag.assert(img.pixels.buffer![offset + 2] == src.pixels.buffer![offset])
                if bytesPerPixel == 4 do
                    Swag.assert(img.pixels.buffer![offset + 3] == src.pixels.buffer![offset + 3])
            }
        }
    }
}

// Encode RLE packets for repeated and literal BGR pixels, then decode them
// without changing the bottom-up pixel buffer.
#test
{
    var src    = Image.create(8, 1, .BGR8)
    let srcBuf = src.pixels.buffer!
    for x in 4
    {
        let offset = cast(u64) x * 3
        srcBuf[offset]     = 10'u8
        srcBuf[offset + 1] = 20'u8
        srcBuf[offset + 2] = 30'u8
    }

    for x in 4 until 8
    {
        let offset = cast(u64) x * 3
        srcBuf[offset]     = cast(u8) x
        srcBuf[offset + 1] = cast(u8) (x + 10)
        srcBuf[offset + 2] = cast(u8) (x + 20)
    }

    var options: Tga.EncodeOptions
    options.rle = true

    let cb    = expect src.encode("memory.tga", options)
    let bytes = nnBytes(cb.toSlice())
    Swag.assert(bytes[2] == TGA_TYPE_RLE_RGB)
    Swag.assert(bytes[18] == 0x83'u8)
    Swag.assert(bytes.count < 18 + src.pixels.count)

    let img = expect Image.decode("encoded-rle.tga", bytes, {})
    Swag.assert(img.pixelFormat == .BGR8)
    Swag.assert(Memory.compare(src.pixels.buffer, img.pixels.buffer, src.pixels.count) == 0)
}

// RLE encoding preserves alpha while converting RGBA input to TGA's BGRA order.
#test
{
    var src    = Image.create(3, 1, .RGBA8)
    let srcBuf = src.pixels.buffer!
    for x in src.width
    {
        let offset = cast(u64) x * 4
        srcBuf[offset]     = 1'u8
        srcBuf[offset + 1] = 2'u8
        srcBuf[offset + 2] = 3'u8
        srcBuf[offset + 3] = 4'u8
    }

    var options: Tga.EncodeOptions
    options.rle = true

    let cb    = expect src.encode("memory.tga", options)
    let bytes = nnBytes(cb.toSlice())
    Swag.assert(bytes[2] == TGA_TYPE_RLE_RGB)
    Swag.assert(bytes[16] == 32'u8)
    Swag.assert(bytes[17] == 8'u8)

    let img = expect Image.decode("encoded-rle-alpha.tga", bytes, {})
    Swag.assert(img.pixelFormat == .BGRA8)
    Swag.assert(img.pixels.buffer != null)
    Swag.assert(img.pixels.buffer[0] == 3'u8)
    Swag.assert(img.pixels.buffer[1] == 2'u8)
    Swag.assert(img.pixels.buffer[2] == 1'u8)
    Swag.assert(img.pixels.buffer[3] == 4'u8)
}
