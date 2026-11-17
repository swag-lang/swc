#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// WOFF1 reconstruction preserves the face and outline even when sfnt padding bytes differ.
#test
{
    let original = loadFontBytes("arial.ttf")
    var woff = expect buildWoffFont(original.toSlice())
    let restored = expect inflateWoff(woff.toSlice())

    let originalFace = expect Face.load(original.toSlice())
    defer originalFace.destroy()
    let restoredFace = expect Face.load(restored.toSlice())
    defer restoredFace.destroy()
    let woffFace = expect Face.load(woff.toSlice())
    defer woffFace.destroy()
    Swag.require(restoredFace.familyName == originalFace.familyName)
    Swag.require(woffFace.familyName == originalFace.familyName)
    Swag.require(restoredFace.glyphCount == originalFace.glyphCount)
    Swag.require(woffFace.glyphCount == originalFace.glyphCount)
    Swag.require(restoredFace.unitsPerEm == originalFace.unitsPerEm)
    Swag.require(woffFace.unitsPerEm == originalFace.unitsPerEm)

    expect originalFace.setPixelSize(0, 20)
    expect restoredFace.setPixelSize(0, 20)
    expect originalFace.loadChar('A')
    expect restoredFace.loadChar('A')
    Swag.require(restoredFace.glyph.advance.x == originalFace.glyph.advance.x)
    let originalPoints = unwrap originalFace.glyph.outline.points
    let restoredPoints = unwrap restoredFace.glyph.outline.points
    Swag.require(restoredFace.glyph.outline.pointCount == originalFace.glyph.outline.pointCount)
    for index in originalFace.glyph.outline.pointCount
    {
        Swag.require(restoredPoints[index].x == originalPoints[index].x)
        Swag.require(restoredPoints[index].y == originalPoints[index].y)
    }

    Swag.require(expect Face.countFaces(woff.toSlice()) == 1)
    Swag.require(expect Face.familyNameAt(woff.toSlice(), 0) == "Arial")
    let metadata = expect Face.metadataAt(woff.toSlice(), 0)
    Swag.require(metadata.familyName == "Arial" and metadata.styleName == "Regular")

    var indexOutcome: Swag.Error
    discard catch Face.loadAt(woff.toSlice(), 1) as indexOutcome
    Swag.require(indexOutcome.value() != null)

    var compressedTables = 0'u32
    for index in readBigU16(&woff, 12)
    {
        let record = 44'u64 + cast(u64, index) * 20
        if readBigU32(&woff, record + 8) < readBigU32(&woff, record + 12) do
            compressedTables += 1
    }
    Swag.require(compressedTables > 0)
    Swag.require(compressedTables < readBigU16(&woff, 12))
}

// WOFF1 declarations cannot extend beyond the file or disagree with its declared length.
#test
{
    let original = loadFontBytes("arial.ttf")
    var woff = expect buildWoffFont(original.toSlice())

    var outcome: Swag.Error
    writeBigU32(&woff, 8, cast(u32, woff.count - 1))
    discard catch inflateWoff(woff.toSlice()) as outcome
    Swag.require(outcome.value() != null)

    outcome = {}
    woff = expect buildWoffFont(original.toSlice())
    writeBigU32(&woff, 48, cast(u32, woff.count + 1))
    discard catch inflateWoff(woff.toSlice()) as outcome
    Swag.require(outcome.value() != null)

    outcome = {}
    woff = expect buildWoffFont(original.toSlice())
    writeBigU32(&woff, 48, 44)
    discard catch inflateWoff(woff.toSlice()) as outcome
    Swag.require(outcome.value() != null)

    outcome = {}
    woff = expect buildWoffFont(original.toSlice())
    let firstTableOffset = readBigU32(&woff, 48)
    writeBigU32(&woff, 24, firstTableOffset)
    writeBigU32(&woff, 28, 4)
    writeBigU32(&woff, 32, 4)
    discard catch inflateWoff(woff.toSlice()) as outcome
    Swag.require(outcome.value() != null)

    outcome = {}
    woff = expect buildWoffFont(original.toSlice())
    writeBigU32(&woff, 68, readBigU32(&woff, 48))
    discard catch inflateWoff(woff.toSlice()) as outcome
    Swag.require(outcome.value() != null)
}

// Metadata follows all font tables, and private data follows metadata at end of file.
#test
{
    let original = loadFontBytes("arial.ttf")
    var woff = expect buildWoffFont(original.toSlice())

    var zlib: Compress.ZLib
    let metadata = expect zlib.compress("font metadata")
    while (woff.count & 3) != 0 do
        woff.add(0)
    let metadataOffset = cast(u32, woff.count)
    woff.add(metadata.toSlice())

    while (woff.count & 3) != 0 do
        woff.add(0)
    let privateOffset = cast(u32, woff.count)
    woff.add(1'u8)
    woff.add(2'u8)
    woff.add(3'u8)

    writeBigU32(&woff, 8, cast(u32, woff.count))
    writeBigU32(&woff, 24, metadataOffset)
    writeBigU32(&woff, 28, cast(u32, metadata.count))
    writeBigU32(&woff, 32, cast(u32, "font metadata".count))
    writeBigU32(&woff, 36, privateOffset)
    writeBigU32(&woff, 40, 3)

    let face = expect Face.load(woff.toSlice())
    defer face.destroy()
    Swag.require(face.familyName == "Arial")

    var trailingBytes: Array'u8
    trailingBytes.add(woff.toSlice())
    trailingBytes.add(0)
    writeBigU32(&trailingBytes, 8, cast(u32, trailingBytes.count))
    var outcome: Swag.Error
    discard catch inflateWoff(trailingBytes.toSlice()) as outcome
    Swag.require(outcome.value() != null)
}

// A compressed table may not expand past or stop short of its declared original length.
#test
{
    let original = loadFontBytes("arial.ttf")
    var woff = expect buildWoffFont(original.toSlice())
    var compressedRecord = Swag.U64.Max
    for index in readBigU16(&woff, 12)
    {
        let record = 44'u64 + cast(u64, index) * 20
        if readBigU32(&woff, record + 8) < readBigU32(&woff, record + 12)
        {
            compressedRecord = record
            break
        }
    }
    Swag.require(compressedRecord != Swag.U64.Max)

    let compressedLength = readBigU32(&woff, compressedRecord + 8)
    let originalLength = readBigU32(&woff, compressedRecord + 12)
    writeBigU32(&woff, compressedRecord + 12, compressedLength + 1)
    writeBigU32(&woff, 16, readBigU32(&woff, 16) - originalLength + compressedLength + 1)

    var outcome: Swag.Error
    discard catch inflateWoff(woff.toSlice()) as outcome
    Swag.require(outcome.value() != null)
}
