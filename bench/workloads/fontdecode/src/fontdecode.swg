using Core, TrueType

#main
{
    let args = Env.arguments()
    Swag.require(args.count >= 6 and args.count <= 10)
    let mode = args.count >= 7 ? args[6] : "file"
    Swag.require(mode == "file" or mode == "memory" or mode == "source")
    let path      = args[1]
    let faceIndex = expect StrConv.toU32(args[2])
    let character = cast(rune, expect StrConv.toU32(args[3]))
    let pixels    = expect StrConv.toU32(args[4])
    let samples   = expect StrConv.toU32(args[5])
    let warmups   = args.count >= 9 ? (expect StrConv.toU32(args[8])) : 5
    Swag.require(samples > 0 and warmups <= Swag.U32.Max - samples)

    if args.count >= 8 do
        Swag.setWorkerCount(expect StrConv.toU32(args[7]))
    if args.count == 10
    {
        Swag.require(args[9] == "prestart")
        Swag.startWorkers()
    }

    var input:  Array'u8
    var source: FontSource
    if mode == "memory" do
        input = expect File.readAllBytes(path)
    elif mode == "source" do
        source = expect FontSource.loadFile(path)

    var openTicks, renderTicks:  u64
    var glyphIndex, width, rows: u32
    var bitmapCrc:               u64
    var advance:                 s32
    for sample in samples + warmups
    {
        let start = Time.monotonicTicks()
        var loaded: *Face?
        catch
        {
            if mode == "memory" do
                loaded = try Face.loadAt(input.toSlice(), faceIndex)
            elif mode == "source" do
                loaded = try source.loadFace(faceIndex)
            else do
                loaded = try Face.loadFile(path, faceIndex)
        }

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
        if sample < warmups do
            continue
        openTicks   += opened - start
        renderTicks += rendered - opened

        if sample + 1 == samples + warmups
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
