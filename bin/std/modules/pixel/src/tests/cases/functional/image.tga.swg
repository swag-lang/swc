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

private func requireTgaDecodeFails(bytes: const [..] u8, options: DecodeOptions)
{
    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try Image.decode("limited.tga", bytes, options) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
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
            let value = cast(u16, (i & 0xFFFF))
            source[1 + i * 2]       = cast(u8, (value & 0xFF))
            source[1 + i * 2 + 1]   = cast(u8, (value >> 8))
            expected[3 + i * 4]     = Tga.expand5(value & 31)
            expected[3 + i * 4 + 1] = Tga.expand5((value >> 5) & 31)
            expected[3 + i * 4 + 2] = Tga.expand5((value >> 10) & 31)
            expected[3 + i * 4 + 3] = alphaFromBit ? (value & 0x8000 ? 255 : 0) : 255
        }

        Tga.decodeTga16Row(source.storage() + 1, actual.storage() + 3, Pixels, alphaFromBit)
        for i in actual.count do
            Swag.require(actual[i] == expected[i])

        for i in actual.count
        {
            actual[i]   = 0xA5
            expected[i] = 0xA5
        }

        for i in Pixels
        {
            let value = cast(u16, ((Pixels - i - 1) & 0xFFFF))
            expected[3 + i * 4]     = Tga.expand5(value & 31)
            expected[3 + i * 4 + 1] = Tga.expand5((value >> 5) & 31)
            expected[3 + i * 4 + 2] = Tga.expand5((value >> 10) & 31)
            expected[3 + i * 4 + 3] = alphaFromBit ? (value & 0x8000 ? 255 : 0) : 255
        }

        Tga.decodeTga16RowReversed(source.storage() + 1, actual.storage() + 3, Pixels, alphaFromBit)
        for i in actual.count do
            Swag.require(actual[i] == expected[i])
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
        let value = cast(u16, ((Pixels - i - 1) & 0xFFFF))
        expected[3 + i * 3]     = Tga.expand5(value & 31)
        expected[3 + i * 3 + 1] = Tga.expand5((value >> 5) & 31)
        expected[3 + i * 3 + 2] = Tga.expand5((value >> 10) & 31)
    }

    Tga.decodeTga15RowReversed(source.storage() + 1, actual.storage() + 3, Pixels)
    for i in actual.count do
        Swag.require(actual[i] == expected[i])
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
                source[i] = cast(u8, ((i * 43 + 17) & 0xFF))
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
                PackedPixel.fillBgr24Row(source.storage() + 1, actual.storage() + 3, pixelCount)
            else do
                PackedPixel.fillBgra32Row(source.storage() + 1, actual.storage() + 3, pixelCount)
            for i in actual.count do
                Swag.require(actual[i] == expected[i])
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
                source[i] = cast(u8, ((i * 37 + 11) & 0xFF))
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
                PackedPixel.reverseBgr24Row(source.storage() + 1, actual.storage() + 3, pixelCount)
            else do
                PackedPixel.reverseBgra32Row(source.storage() + 1, actual.storage() + 3, pixelCount)
            for i in actual.count do
                Swag.require(actual[i] == expected[i])
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
        pixel[1 + channel] = cast(u8, (channel * 53 + 17))

    for mismatch in Candidates + 1
    {
        for candidate in Candidates
        {
            for channel in 4 do
                candidates[1 + candidate * 4 + channel] = pixel[1 + channel]
        }

        if mismatch < Candidates do
            candidates[1 + mismatch * 4 + 2] ^= 0xFF
        Swag.require(PackedPixel.countSame32(pixel.storage() + 1, candidates.storage() + 1, Candidates) == mismatch)
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
    for i in cast(u64, Width) * Height do
        cb.addNative(cast(u16, ((i * 1907 + 123) & 0x7FFF)))

    let img = expect Image.decode("memory.tga", nnBytes(cb.toSlice()), {})
    Swag.require(img.width == Width and img.height == Height and img.pixelFormat == .BGR8)
    for i in cast(u64, Width) * Height
    {
        let sourceY = i / Width
        let x       = i % Width
        let targetY = Height - sourceY - 1
        let offset  = (targetY * Width + x) * 3
        let value   = cast(u32, ((i * 1907 + 123) & 0x7FFF))
        Swag.require(img.pixels.storage()[offset] == Tga.expand5(value & 31))
        Swag.require(img.pixels.storage()[offset + 1] == Tga.expand5((value >> 5) & 31))
        Swag.require(img.pixels.storage()[offset + 2] == Tga.expand5((value >> 10) & 31))
    }
}

// Decode right-origin packed rows through a full vector and an odd tail on each row.
#test
{
    const Width  = 17'u16
    const Height = 2'u16
    scope
    {
        var cb: ConcatBuffer
        addTgaImageHeader(&cb, TGA_TYPE_RGB, 15, TGA_DESC_TOP | TGA_DESC_RIGHT, Width, Height)
        for i in cast(u64, Width) * Height do
            cb.addNative(cast(u16, ((i * 1907 + 123) & 0x7FFF)))

        let img = expect Image.decode("memory.tga", nnBytes(cb.toSlice()), {})
        Swag.require(img.width == Width and img.height == Height and img.pixelFormat == .BGR8)
        for i in cast(u64, Width) * Height
        {
            let sourceY = i / Width
            let sourceX = i % Width
            let targetY = Height - sourceY - 1
            let targetX = Width - sourceX - 1
            let offset  = (targetY * Width + targetX) * 3
            let value   = cast(u32, ((i * 1907 + 123) & 0x7FFF))
            Swag.require(img.pixels.storage()[offset] == Tga.expand5(value & 31))
            Swag.require(img.pixels.storage()[offset + 1] == Tga.expand5((value >> 5) & 31))
            Swag.require(img.pixels.storage()[offset + 2] == Tga.expand5((value >> 10) & 31))
        }
    }

    scope
    {
        var cb: ConcatBuffer
        addTgaImageHeader(&cb, TGA_TYPE_RGB, 16, TGA_DESC_TOP | TGA_DESC_RIGHT | 1, Width, Height)
        for i in cast(u64, Width) * Height do
            cb.addNative(cast(u16, (i * 1907 + 123)))

        let img = expect Image.decode("memory.tga", nnBytes(cb.toSlice()), {})
        Swag.require(img.width == Width and img.height == Height and img.pixelFormat == .BGRA8)
        for i in cast(u64, Width) * Height
        {
            let sourceY = i / Width
            let sourceX = i % Width
            let targetY = Height - sourceY - 1
            let targetX = Width - sourceX - 1
            let offset  = (targetY * Width + targetX) * 4
            let value   = cast(u32, ((i * 1907 + 123) & 0xFFFF))
            Swag.require(img.pixels.storage()[offset] == Tga.expand5(value & 31))
            Swag.require(img.pixels.storage()[offset + 1] == Tga.expand5((value >> 5) & 31))
            Swag.require(img.pixels.storage()[offset + 2] == Tga.expand5((value >> 10) & 31))
            Swag.require(img.pixels.storage()[offset + 3] == (value & 0x8000 ? 255'u8 : 0'u8))
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
        let bytesPerPixel = cast(u64, (bpp / 8))
        for rightMode in 2
        {
            var cb: ConcatBuffer
            let descriptor = TGA_DESC_TOP |
                             (rightMode ? TGA_DESC_RIGHT : 0) |
                             (bpp == 32 ? 8'u8 : 0'u8)
            addTgaImageHeader(&cb, TGA_TYPE_RGB, bpp, descriptor, Width, Height)
            for pixel in cast(u64, Width) * Height
            {
                for channel in bytesPerPixel do
                    cb.addNative(cast(u8, ((pixel * 29 + channel * 71 + 13) & 0xFF)))
            }

            let img = expect Image.decode("memory.tga", nnBytes(cb.toSlice()), {})
            Swag.require(img.width == Width and img.height == Height)
            Swag.require(img.pixelFormat == (bpp == 24 ? .BGR8 : .BGRA8))
            for pixel in cast(u64, Width) * Height
            {
                let sourceY = pixel / Width
                let sourceX = pixel % Width
                let targetY = Height - sourceY - 1
                let targetX = rightMode ? Width - sourceX - 1 : sourceX
                let offset  = (targetY * Width + targetX) * bytesPerPixel
                for channel in bytesPerPixel do
                    Swag.require(img.pixels.storage()[offset + channel] == cast(u8, ((pixel * 29 + channel * 71 + 13) & 0xFF)))
            }
        }
    }
}

// A 32-bit sample's last byte is alpha only when the descriptor declares attribute bits.
#test
{
    for rle in 2
    {
        for alphaBits in [0'u8, 8'u8]
        {
            var cb: ConcatBuffer
            let imageType = rle ? TGA_TYPE_RLE_RGB : TGA_TYPE_RGB
            addTgaImageHeader(&cb, imageType, 32, alphaBits, 1, 1)
            if rle do
                cb.addNative(0'u8)     // One raw RLE packet.
            cb.addNative(10'u8)
            cb.addNative(20'u8)
            cb.addNative(30'u8)
            cb.addNative(37'u8)

            let image = expect Image.decode("alpha-depth.tga", nnBytes(cb.toSlice()), {})
            Swag.require(image.pixelFormat == .BGRA8)
            Swag.require(image.pixels.count == 4)
            Swag.require(image.pixels[0] == 10 and image.pixels[1] == 20 and image.pixels[2] == 30)
            Swag.require(image.pixels[3] == (alphaBits == 0 ? 255'u8 : 37'u8))
        }
    }
}

// Decoder and encoder registries recognise TGA files.
#test
{
    Swag.require(Image.canLoad("in.tga"))
    Swag.require(Image.canSave("out.tga"))
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
    Swag.require(img.width == 2)
    Swag.require(img.height == 2)
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 10'u8)
    Swag.require(img.pixels.buffer[1] == 20'u8)
    Swag.require(img.pixels.buffer[2] == 30'u8)
    Swag.require(img.pixels.buffer[9] == 100'u8)
    Swag.require(img.pixels.buffer[10] == 110'u8)
    Swag.require(img.pixels.buffer[11] == 120'u8)
}

// Load larger RGB/RGBA fixtures copied from the historical pixel test data.
#test
{
    let rgb = expect Image.load(getTestDataPath("rgb.tga"))
    Swag.require(rgb.isValid())
    Swag.require(rgb.width == 660)
    Swag.require(rgb.height == 441)
    Swag.require(rgb.pixelFormat == .BGR8)
    Swag.require(rgb.pixels.count == 873180)
    Swag.require(rgb.pixels.buffer != null)
    Swag.require(rgb.pixels.buffer[0] == 201'u8)
    Swag.require(rgb.pixels.buffer[1] == 205'u8)
    Swag.require(rgb.pixels.buffer[2] == 194'u8)

    let rgba = expect Image.load(getTestDataPath("rgba.tga"))
    Swag.require(rgba.isValid())
    Swag.require(rgba.width == 660)
    Swag.require(rgba.height == 441)
    Swag.require(rgba.pixelFormat == .BGRA8)
    Swag.require(rgba.pixels.count == 1164240)
    Swag.require(rgba.pixels.buffer != null)
    Swag.require(rgba.pixels.buffer[0] == 201'u8)
    Swag.require(rgba.pixels.buffer[1] == 205'u8)
    Swag.require(rgba.pixels.buffer[2] == 194'u8)
    Swag.require(rgba.pixels.buffer[3] == 255'u8)
}

// Load RLE RGB/RGBA fixtures copied from the historical pixel test data.
#test
{
    let rle24 = expect Image.load(getTestDataPath("rle24.tga"))
    Swag.require(rle24.isValid())
    Swag.require(rle24.width == 660)
    Swag.require(rle24.height == 441)
    Swag.require(rle24.pixelFormat == .BGR8)
    Swag.require(rle24.pixels.buffer != null)
    Swag.require(rle24.pixels.buffer[0] == 201'u8)
    Swag.require(rle24.pixels.buffer[1] == 205'u8)
    Swag.require(rle24.pixels.buffer[2] == 194'u8)

    let rle32 = expect Image.load(getTestDataPath("rle32.tga"))
    Swag.require(rle32.isValid())
    Swag.require(rle32.width == 660)
    Swag.require(rle32.height == 441)
    Swag.require(rle32.pixelFormat == .BGRA8)
    Swag.require(rle32.pixels.buffer != null)
    Swag.require(rle32.pixels.buffer[0] == 201'u8)
    Swag.require(rle32.pixels.buffer[1] == 205'u8)
    Swag.require(rle32.pixels.buffer[2] == 194'u8)
    Swag.require(rle32.pixels.buffer[3] == 255'u8)
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
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 8'u8)
    Swag.require(img.pixels.buffer[1] == 9'u8)
    Swag.require(img.pixels.buffer[2] == 10'u8)
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
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 7'u8)
    Swag.require(img.pixels.buffer[1] == 8'u8)
    Swag.require(img.pixels.buffer[2] == 9'u8)
    Swag.require(img.pixels.buffer[6] == 1'u8)
    Swag.require(img.pixels.buffer[7] == 2'u8)
    Swag.require(img.pixels.buffer[8] == 3'u8)
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
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 4'u8)
    Swag.require(img.pixels.buffer[1] == 5'u8)
    Swag.require(img.pixels.buffer[2] == 6'u8)
    Swag.require(img.pixels.buffer[3] == 1'u8)
    Swag.require(img.pixels.buffer[4] == 2'u8)
    Swag.require(img.pixels.buffer[5] == 3'u8)
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
    Swag.require(img.pixelFormat == .BGRA8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 0'u8)
    Swag.require(img.pixels.buffer[1] == 0'u8)
    Swag.require(img.pixels.buffer[2] == 255'u8)
    Swag.require(img.pixels.buffer[3] == 255'u8)
    Swag.require(img.pixels.buffer[4] == 0'u8)
    Swag.require(img.pixels.buffer[5] == 255'u8)
    Swag.require(img.pixels.buffer[6] == 0'u8)
    Swag.require(img.pixels.buffer[7] == 0'u8)
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
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 5'u8)
    Swag.require(img.pixels.buffer[1] == 5'u8)
    Swag.require(img.pixels.buffer[2] == 5'u8)
    Swag.require(img.pixels.buffer[6] == 15'u8)
    Swag.require(img.pixels.buffer[7] == 15'u8)
    Swag.require(img.pixels.buffer[8] == 15'u8)
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
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 10'u8)
    Swag.require(img.pixels.buffer[1] == 20'u8)
    Swag.require(img.pixels.buffer[2] == 30'u8)
    Swag.require(img.pixels.buffer[3] == 40'u8)
    Swag.require(img.pixels.buffer[4] == 50'u8)
    Swag.require(img.pixels.buffer[5] == 60'u8)
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
    Swag.require(img.pixelFormat == .BGRA8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 3'u8)
    Swag.require(img.pixels.buffer[1] == 4'u8)
    Swag.require(img.pixels.buffer[2] == 5'u8)
    Swag.require(img.pixels.buffer[3] == 6'u8)
}

// A 16-bit indexed palette's high bit is alpha only when the descriptor declares it.
#test
{
    for rle in 2
    {
        for alphaDeclared in 2
        {
            var cb: ConcatBuffer
            var h:  TgaH
            h.colorMapType   = 1'u8
            h.imageTypeCode  = rle ? TGA_TYPE_RLE_MAP : TGA_TYPE_MAP
            h.colorMapLength = 2'u16
            h.colorMapBpp    = 16'u8
            h.width          = 2'u16
            h.height         = 1'u16
            h.bitsPerPixel   = 8'u8
            h.descriptorByte = alphaDeclared ? 1'u8 : 0'u8
            cb.addStruct(h)
            cb.addNative(0x7C00'u16)
            cb.addNative(0xFC00'u16)
            if rle do
                cb.addNative(0x01'u8)
            cb.addNative(0'u8)
            cb.addNative(1'u8)

            let img = expect Image.decode("memory.tga", nnBytes(cb.toSlice()), {})
            Swag.require(img.pixelFormat == .BGRA8)
            let pixels = img.pixels.storage()
            Swag.require(pixels[0] == 0'u8)
            Swag.require(pixels[1] == 0'u8)
            Swag.require(pixels[2] == 255'u8)
            Swag.require(pixels[3] == (alphaDeclared ? 0'u8 : 255'u8))
            Swag.require(pixels[4] == 0'u8)
            Swag.require(pixels[5] == 0'u8)
            Swag.require(pixels[6] == 255'u8)
            Swag.require(pixels[7] == 255'u8)
        }
    }
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
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 1'u8)
    Swag.require(img.pixels.buffer[9] == 1'u8)
    Swag.require(img.pixels.buffer[10] == 2'u8)
    Swag.require(img.pixels.buffer[11] == 3'u8)
}

// Decode mixed raw and repeated packets that cross rows in every origin mode.
#test
{
    const Width  = 17'u16
    const Height = 3'u16
    const Pixels = cast(u64, Width) * Height
    for bpp in [24'u8, 32'u8]
    {
        let bytesPerPixel = cast(u64, (bpp / 8))
        for topMode in 2
        {
            for rightMode in 2
            {
                let descriptor = (topMode ? TGA_DESC_TOP : 0) |
                                 (rightMode ? TGA_DESC_RIGHT : 0) |
                                 (bpp == 32 ? 8'u8 : 0'u8)
                var cb:       ConcatBuffer
                var expected: Array'u8
                expected.resize(Pixels * bytesPerPixel)
                addTgaImageHeader(&cb, TGA_TYPE_RLE_RGB, bpp, descriptor, Width, Height)

                cb.addNative(19'u8)
                for pixel in 20'u64
                {
                    for channel in bytesPerPixel
                    {
                        let value = cast(u8, ((pixel * 29 + channel * 71 + 13) & 0xFF))
                        cb.addNative(value)
                        expected[pixel * bytesPerPixel + channel] = value
                    }
                }

                cb.addNative(0x91'u8)
                for channel in bytesPerPixel do
                    cb.addNative(cast(u8, ((channel * 53 + 91) & 0xFF)))
                for pixel in 18'u64
                {
                    for channel in bytesPerPixel do
                        expected[(20 + pixel) * bytesPerPixel + channel] = cast(u8, ((channel * 53 + 91) & 0xFF))
                }

                cb.addNative(12'u8)
                for packetPixel in 13'u64
                {
                    let pixel = 38 + packetPixel
                    for channel in bytesPerPixel
                    {
                        let value = cast(u8, ((pixel * 29 + channel * 71 + 13) & 0xFF))
                        cb.addNative(value)
                        expected[pixel * bytesPerPixel + channel] = value
                    }
                }

                let img = expect Image.decode("memory.tga", nnBytes(cb.toSlice()), {})
                Swag.require(img.pixelFormat == (bpp == 24 ? .BGR8 : .BGRA8))
                for pixel in Pixels
                {
                    let sourceY = pixel / Width
                    let sourceX = pixel % Width
                    let targetY = topMode ? Height - sourceY - 1 : sourceY
                    let targetX = rightMode ? Width - sourceX - 1 : sourceX
                    let offset  = (targetY * Width + targetX) * bytesPerPixel
                    for channel in bytesPerPixel do
                        Swag.require(img.pixels.storage()[offset + channel] == expected[pixel * bytesPerPixel + channel])
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
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 1'u8)
    Swag.require(img.pixels.buffer[3] == 4'u8)
    Swag.require(img.pixels.buffer[6] == 7'u8)
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
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 9'u8)
    Swag.require(img.pixels.buffer[3] == 10'u8)
    Swag.require(img.pixels.buffer[6] == 11'u8)
}

// Decode metadata without allocating pixels.
#test
{
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 24'u8, 0'u8, 2'u16, 2'u16)

    var opts: DecodeOptions
    opts.decodePixels = false

    let img = expect Image.decode("meta.tga", nnBytes(cb.toSlice()), opts)
    Swag.require(img.width == 2)
    Swag.require(img.height == 2)
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(not img.isValid())
}

// TGA decoding enforces pixel and decoded-byte limits before allocation and metadata return.
#test
{
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 24'u8, 0'u8, 2'u16, 2'u16)
    for i in 12 do
        cb.addNative(cast(u8, i))
    let bytes = nnBytes(cb.toSlice())

    var options: DecodeOptions
    options.maxPixels = 3
    requireTgaDecodeFails(bytes, options)

    options = {}
    options.maxDecodedBytes = 11
    requireTgaDecodeFails(bytes, options)

    options = {}
    options.decodePixels = false
    options.maxPixels = 3
    requireTgaDecodeFails(bytes, options)

    options = {}
    options.decodePixels = false
    options.maxDecodedBytes = 11
    requireTgaDecodeFails(bytes, options)
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
    var err28Outcome: Swag.Error
    catch { img = try Image.decode("bad.tga", nnBytes(cb.toSlice()), {}) } as err28Outcome
    let err28 = err28Outcome.value()
    Swag.require(err28 != null)
}

// Error: color-mapped images require palette data.
#test
{
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_MAP, 8'u8, 0'u8, 1'u16, 1'u16)
    cb.addNative(0'u8)

    var img: Image
    var err29Outcome: Swag.Error
    catch { img = try Image.decode("bad.tga", nnBytes(cb.toSlice()), {}) } as err29Outcome
    let err29 = err29Outcome.value()
    Swag.require(err29 != null)
}

// Error: row interleaving modes are unsupported and cannot be decoded as sequential rows.
#test
{
    var cb: ConcatBuffer
    addTgaImageHeader(&cb, TGA_TYPE_RGB, 24'u8, 0x40'u8, 1'u16, 3'u16)
    cb.addNative(1'u8)
    cb.addNative(2'u8)
    cb.addNative(3'u8)
    cb.addNative(4'u8)
    cb.addNative(5'u8)
    cb.addNative(6'u8)
    cb.addNative(7'u8)
    cb.addNative(8'u8)
    cb.addNative(9'u8)

    var img: Image
    var interlaceErrorOutcome: Swag.Error
    catch { img = try Image.decode("interleaved.tga", nnBytes(cb.toSlice()), {}) } as interlaceErrorOutcome
    Swag.require(interlaceErrorOutcome.value() != null)
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
            src.pixels.storage()[i] = cast(u8, ((i * 37 + 19) & 0xFF))

        let cb  = expect src.encode("memory.tga")
        let img = expect Image.decode("memory.tga", nnBytes(cb.toSlice()), {})
        let bytesPerPixel = cast(u64, src.bytesPerPixel)
        Swag.require(cb.count() == #sizeof(TgaH) + src.pixels.count)
        Swag.require(img.pixelFormat == (bytesPerPixel == 3 ? .BGR8 : .BGRA8))
        for pixel in cast(u64, Width) * Height
        {
            let offset = pixel * bytesPerPixel
            Swag.require(img.pixels.storage()[offset] == src.pixels.storage()[offset + 2])
            Swag.require(img.pixels.storage()[offset + 1] == src.pixels.storage()[offset + 1])
            Swag.require(img.pixels.storage()[offset + 2] == src.pixels.storage()[offset])
            if bytesPerPixel == 4 do
                Swag.require(img.pixels.storage()[offset + 3] == src.pixels.storage()[offset + 3])
        }
    }
}

// Encode BGR8 and round-trip through the decoder.
#test
{
    let path = makeTempTgaPath()
    defer discard catch File.delete(path.toString())
    var src    = Image.create(2, 1, .BGR8)
    let srcBuf = src.pixels.storage()
    srcBuf[0] = 1'u8
    srcBuf[1] = 2'u8
    srcBuf[2] = 3'u8
    srcBuf[3] = 4'u8
    srcBuf[4] = 5'u8
    srcBuf[5] = 6'u8

    let cb = expect src.encode("memory.tga")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 1'u8)
    Swag.require(img.pixels.buffer[5] == 6'u8)
}

// Encode RGB8 by swapping R/B into the on-disk BGR order.
#test
{
    let path = makeTempTgaPath()
    defer discard catch File.delete(path.toString())
    var src    = Image.create(1, 1, .RGB8)
    let srcBuf = src.pixels.storage()
    srcBuf[0] = 10'u8
    srcBuf[1] = 20'u8
    srcBuf[2] = 30'u8

    let cb = expect src.encode("memory.tga")
    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 30'u8)
    Swag.require(img.pixels.buffer[1] == 20'u8)
    Swag.require(img.pixels.buffer[2] == 10'u8)
}

// Encode RGBA8 with descriptor alpha bits and preserve alpha through round-trip.
#test
{
    let path = makeTempTgaPath()
    defer discard catch File.delete(path.toString())
    var src    = Image.create(1, 1, .RGBA8)
    let srcBuf = src.pixels.storage()
    srcBuf[0] = 1'u8
    srcBuf[1] = 2'u8
    srcBuf[2] = 3'u8
    srcBuf[3] = 4'u8

    let cb = expect src.encode("memory.tga")
    cb.makeLinear()
    let bytes = nnBytes(cb.toSlice())
    Swag.require(bytes != null)
    let h = cast(const *TgaH, bytes.buffer)
    Swag.require(h.imageTypeCode == TGA_TYPE_RGB)
    Swag.require(h.bitsPerPixel == 32'u8)
    Swag.require(h.descriptorByte == 8'u8)

    discard expect File.writeAllBytes(path.toString(), cb)
    let img = expect Image.load(path.toString())
    Swag.require(img.pixelFormat == .BGRA8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 3'u8)
    Swag.require(img.pixels.buffer[1] == 2'u8)
    Swag.require(img.pixels.buffer[2] == 1'u8)
    Swag.require(img.pixels.buffer[3] == 4'u8)
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
        Memory.set(src.pixels.storage(), 73, src.pixels.count)

        var cb = expect src.encode("memory.tga", options)
        cb.makeLinear()
        let bytes         = nnBytes(cb.toSlice())
        let bytesPerPixel = cast(u64, src.bytesPerPixel)
        Swag.require(bytes.count == #sizeof(TgaH) + 3 * (1 + bytesPerPixel))
        Swag.require(bytes[#sizeof(TgaH)] == 0xFF)
        Swag.require(bytes[#sizeof(TgaH) + 1 + bytesPerPixel] == 0xFF)
        Swag.require(bytes[#sizeof(TgaH) + 2 + 2 * bytesPerPixel] == 0)

        let img = expect Image.decode("memory.tga", bytes, {})
        for i in img.pixels.count do
            Swag.require(img.pixels.storage()[i] == 73)
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
            src.pixels.storage()[i] = cast(u8, ((i * 37 + 19) & 0xFF))

        var cb = expect src.encode("memory.tga", options)
        cb.makeLinear()
        let bytes         = nnBytes(cb.toSlice())
        let bytesPerPixel = cast(u64, src.bytesPerPixel)
        Swag.require(bytes[#sizeof(TgaH)] == 0x7F)
        Swag.require(bytes[#sizeof(TgaH) + 1 + 128 * bytesPerPixel] == 2)

        let img = expect Image.decode("memory.tga", bytes, {})
        Swag.require(img.pixelFormat == (pixelFormat == .BGR8 or pixelFormat == .RGB8 ? .BGR8 : .BGRA8))
        for pixel in cast(u64, Width)
        {
            let offset = pixel * bytesPerPixel
            if pixelFormat == .BGR8 or pixelFormat == .BGRA8
            {
                for channel in bytesPerPixel do
                    Swag.require(img.pixels.storage()[offset + channel] == src.pixels.storage()[offset + channel])
            }
            else
            {
                Swag.require(img.pixels.storage()[offset] == src.pixels.storage()[offset + 2])
                Swag.require(img.pixels.storage()[offset + 1] == src.pixels.storage()[offset + 1])
                Swag.require(img.pixels.storage()[offset + 2] == src.pixels.storage()[offset])
                if bytesPerPixel == 4 do
                    Swag.require(img.pixels.storage()[offset + 3] == src.pixels.storage()[offset + 3])
            }
        }
    }
}

// Encode RLE packets for repeated and literal BGR pixels, then decode them
// without changing the bottom-up pixel buffer.
#test
{
    var src    = Image.create(8, 1, .BGR8)
    let srcBuf = src.pixels.storage()
    for x in 4
    {
        let offset = cast(u64, x) * 3
        srcBuf[offset]     = 10'u8
        srcBuf[offset + 1] = 20'u8
        srcBuf[offset + 2] = 30'u8
    }

    for x in 4 until 8
    {
        let offset = cast(u64, x) * 3
        srcBuf[offset]     = cast(u8, x)
        srcBuf[offset + 1] = cast(u8, (x + 10))
        srcBuf[offset + 2] = cast(u8, (x + 20))
    }

    var options: Tga.EncodeOptions
    options.rle = true

    let cb    = expect src.encode("memory.tga", options)
    let bytes = nnBytes(cb.toSlice())
    Swag.require(bytes[2] == TGA_TYPE_RLE_RGB)
    Swag.require(bytes[18] == 0x83'u8)
    Swag.require(bytes.count < 18 + src.pixels.count)

    let img = expect Image.decode("encoded-rle.tga", bytes, {})
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(Memory.compare(src.pixels.storage(), img.pixels.storage(), src.pixels.count) == 0)
}

// RLE encoding preserves alpha while converting RGBA input to TGA's BGRA order.
#test
{
    var src    = Image.create(3, 1, .RGBA8)
    let srcBuf = src.pixels.storage()
    for x in src.width
    {
        let offset = cast(u64, x) * 4
        srcBuf[offset]     = 1'u8
        srcBuf[offset + 1] = 2'u8
        srcBuf[offset + 2] = 3'u8
        srcBuf[offset + 3] = 4'u8
    }

    var options: Tga.EncodeOptions
    options.rle = true

    let cb    = expect src.encode("memory.tga", options)
    let bytes = nnBytes(cb.toSlice())
    Swag.require(bytes[2] == TGA_TYPE_RLE_RGB)
    Swag.require(bytes[16] == 32'u8)
    Swag.require(bytes[17] == 8'u8)

    let img = expect Image.decode("encoded-rle-alpha.tga", bytes, {})
    Swag.require(img.pixelFormat == .BGRA8)
    Swag.require(img.pixels.buffer != null)
    Swag.require(img.pixels.buffer[0] == 3'u8)
    Swag.require(img.pixels.buffer[1] == 2'u8)
    Swag.require(img.pixels.buffer[2] == 1'u8)
    Swag.require(img.pixels.buffer[3] == 4'u8)
}
