using Core, Pixel

// Both a script and a linked consumer run this through Pixel's imported decoder registry.
func checkImportedPng()
{
    // A two-pixel RGBA PNG, independent of Pixel's encoder.
    const Encoded: [?] u8 = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0xF4, 0x22, 0x7F,
        0x8A, 0x00, 0x00, 0x00, 0x11, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xE0, 0x12, 0x91, 0x3B,
        0xA1, 0x61, 0x64, 0x93, 0x02, 0x00, 0x07, 0x93, 0x01, 0xFF, 0x06, 0x3F, 0x76, 0x48, 0x00, 0x00,
        0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]
    const Pixels: [?] u8 = [10, 20, 30, 200, 40, 50, 60, 100]

    let tempDir      = Env.getSpecialDirectory(.Temp)
    var name: String = "swag_imported_png_"
    name += Guid64.random().toString()
    name += ".png"
    let path = Path.combine(tempDir.toString(), name.toString())
    defer discard catch File.delete(path.toString())

    let written = expect File.writeAllBytes(path.toString(), Encoded[to])
    Swag.require(written == Encoded.count)

    let decoded = expect Image.load(path.toString())
    Swag.require(decoded.width == 2 and decoded.height == 1)
    Swag.require(decoded.pixelFormat == .RGBA8)
    Swag.require(decoded.pixels.count == Pixels.count)
    for expected, index in Pixels do
        Swag.require(decoded.pixels.storage()[index] == expected)

    let probe = expect Image.load(path.toString(), {decodePixels: false})
    Swag.require(probe.width == decoded.width and probe.height == decoded.height)
    Swag.require(probe.pixelFormat == decoded.pixelFormat)
    Swag.require(probe.pixels.count == 0)
}

#main
{
    checkImportedPng()
    Swag.print("SWAG_IMPORTED_PNG_RAN\n")
}
