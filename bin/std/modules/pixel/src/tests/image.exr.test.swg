#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

#test
{
    var source  = Image.create(3, 2, .RGBF16)
    let samples = cast([*] u16) source.pixels.buffer!
    const Values: [6] u16 = [0x0000, 0x3C00, 0x4000, 0x3800, 0xC000, 0x7BFF]
    for i in 18 do
        samples[i] = Values[i % Values.count]

    let encoded = expect source.encode("memory.exr")
    let decoded = expect Image.decode("memory.exr", nnBytes(encoded.toSlice()))
    assertImage(decoded, 3, 2, .RGBF16)
    Swag.assert(Memory.compare(source.pixels.buffer, decoded.pixels.buffer, source.byteCount) == 0)
}

#test
{
    for format in [PixelFormat.GrayF16, PixelFormat.GrayAlphaF16, PixelFormat.GrayF32, PixelFormat.GrayAlphaF32]
    {
        var source = Image.create(3, 2, format)
        if format.bitDepth() == 16
        {
            let samples = cast([*] u16) source.pixels.buffer!
            const Values: [6] u16 = [0x0000, 0x3400, 0x3800, 0x3C00, 0x4000, 0xC000]
            for i in source.byteCount / 2 do
                samples[i] = Values[i % Values.count]
        }
        else
        {
            let samples = cast([*] f32) source.pixels.buffer!
            const Values: [6] f32 = [-2.0, -0.25, 0.0, 0.5, 1.0, 8.0]
            for i in source.byteCount / 4 do
                samples[i] = Values[i % Values.count]
        }

        let encoded = expect source.encode("gray.exr")
        let decoded = expect Image.decode("gray.exr", nnBytes(encoded.toSlice()))
        assertImage(decoded, 3, 2, format)
        Swag.assert(Memory.compare(source.pixels.buffer, decoded.pixels.buffer, source.byteCount) == 0)
    }
}

#test
{
    var source  = Image.create(2, 2, .RGBAF32)
    let samples = cast([*] f32) source.pixels.buffer!
    const Values: [8] f32 = [-2.0, -0.25, 0.0, 0.125, 0.5, 1.0, 4.0, 65504.0]
    for i in 16 do
        samples[i] = Values[i % Values.count]

    let encoded = expect source.encode("float.exr")
    let decoded = expect Image.decode("float.exr", nnBytes(encoded.toSlice()))
    assertImage(decoded, 2, 2, .RGBAF32)
    Swag.assert(Memory.compare(source.pixels.buffer, decoded.pixels.buffer, source.byteCount) == 0)
}

#test
{
    var source = Image.create(2, 1, .RGBA8)
    let bytes  = source.pixels.buffer!
    bytes[0] = 17
    bytes[1] = 34
    bytes[2] = 51
    bytes[3] = 68
    bytes[4] = 85
    bytes[5] = 102
    bytes[6] = 119
    bytes[7] = 136
    let encoded = expect source.encode("integer.exr")
    let decoded = expect Image.decode("integer.exr", nnBytes(encoded.toSlice()))
    assertImage(decoded, 2, 1, .RGBAF16)
    Swag.assert(decoded.pixelColor(0, 0).argb == source.pixelColor(0, 0).argb)
    Swag.assert(decoded.pixelColor(1, 0).argb == source.pixelColor(1, 0).argb)

    var options: DecodeOptions
    options.decodePixels = false
    let header = expect Image.decode("integer.exr", nnBytes(encoded.toSlice()), options)
    Swag.assert(header.width == 2 and header.height == 1 and header.pixelFormat == .RGBAF16 and !header.isValid())
}

// ZIP byte prediction and even/odd shuffling are exactly reversible before Deflate is involved.
#test
{
    var original: [257] u8
    for i in original.count do
        original[i] = cast(u8) ((i * 73 + 19) & 0xFF)
    var predicted: [257] u8
    predicted[0] = original[0]
    for i in rangeTo(1'u64, original.count - 1) do
        predicted[i] = cast(u8) ((cast(s32) original[i] - original[i - 1] + 128) & 0xFF)
    var packed: [257] u8
    var even = 0'u64
    var odd  = (original.count + 1) / 2
    for i in original.count
    {
        if i & 1
        {
            packed[odd] = predicted[i]
            odd         += 1
        }
        else
        {
            packed[even] = predicted[i]
            even         += 1
        }
    }

    Exr.undoZipPredictor(packed)
    Swag.assert(Memory.compare(original.buffer, packed.buffer, original.count) == 0)
}

#test
{
    const Invalid: [8] u8 = [0, 1, 2, 3, 4, 5, 6, 7]
    discard catch Image.decode("bad.exr", Invalid) as error
    Swag.assert(error != null)
}
