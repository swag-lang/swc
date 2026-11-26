using Core, TrueType

#main
{
    let args = Env.arguments()
    Swag.require(args.count == 6)
    let path      = args[1]
    let faceIndex = expect StrConv.toU32(args[2])
    let character = cast(rune, expect StrConv.toU32(args[3]))
    let pixels    = expect StrConv.toU32(args[4])
    let samples   = expect StrConv.toU32(args[5])
    Swag.require(samples > 0)

    const Warmups = 5
    var openTicks, renderTicks:  u64
    var glyphIndex, width, rows: u32
    var bitmapCrc:               u64
    var advance:                 s32
    for sample in samples + Warmups
    {
        let start = Time.monotonicTicks()
        var loaded: *Face?
        catch { loaded = try Face.loadFile(path, faceIndex) }
        if not loaded
        {
            Console.println("rejected")
            return
        }

        let face: *Face = loaded
        defer face.destroy()
        expect face.setPixelSize(0, pixels)
        let opened = Time.monotonicTicks()
        expect face.loadChar(character, .Render)
        let rendered = Time.monotonicTicks()
        if sample < Warmups do
            continue
        openTicks   += opened - start
        renderTicks += rendered - opened

        if sample + 1 == samples + Warmups
        {
            glyphIndex = face.glyphIndex(character)
            advance    = face.glyph.advance.x
            let bitmap = &face.glyph.bitmap
            width = bitmap.width
            rows  = bitmap.rows
            Swag.require(glyphIndex > 0 and width > 0 and rows > 0 and bitmap.pitch > 0)
            let bytes = cast(u64, bitmap.pitch) * bitmap.rows
            bitmapCrc = Hash.Crc64.compute(Swag.makeSlice(unwrap bitmap.buffer, bytes))
        }
    }

    let nanosPerSample = 1_000_000_000.0 / (cast(f64, Time.monotonicFrequency()) * samples)
    let openNs         = cast(u64, cast(f64, openTicks) * nanosPerSample)
    let renderNs       = cast(u64, cast(f64, renderTicks) * nanosPerSample)
    Console.println(openNs, " ", renderNs, " ", glyphIndex, " ", advance, " ", width, " ", rows, " ", bitmapCrc)
}
