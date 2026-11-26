#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// A bare font file is a collection holding one face.
#test
{
    let bytes = loadFontBytes("arial.ttf")
    let count = expect Face.countFaces(bytes.toSlice())
    Swag.require(count == 1)

    let face = expect Face.loadAt(bytes.toSlice(), 0)
    defer face.destroy()
    Swag.require(face.familyName == "Arial")
}

// Counting faces rejects empty collections and validates every declared offset.
#test
{
    var truncated: Array'u8
    truncated.resize(12)
    writeBigU32(&truncated, 0, imageTag('t'u32, 't'u32, 'c'u32, 'f'u32))

    var emptyOutcome: Swag.Error
    discard catch Face.countFaces(truncated.toSlice()) as emptyOutcome
    Swag.require(emptyOutcome.value() != null)

    writeBigU32(&truncated, 8, 1)

    var truncatedOutcome: Swag.Error
    discard catch Face.countFaces(truncated.toSlice()) as truncatedOutcome
    Swag.require(truncatedOutcome.value() != null)
}

// A face reports the version, designer, and copyright its name table declares.
#test
{
    let bytes = loadFontBytes("segoeui.ttf")
    let face  = expect Face.load(bytes.toSlice())
    defer face.destroy()
    Swag.require(Utf8.startsWith(face.version.toString(), "Version "))
    Swag.require(face.copyright.indexOf("Microsoft") != Swag.U64.Max)
}

// Every face of a collection loads independently, and the index selects which one.
#test
{
    let bytes = buildFontCollection(["arial.ttf", "arialbd.ttf"])
    let count = expect Face.countFaces(bytes.toSlice())
    Swag.require(count == 2)

    let regular = expect Face.loadAt(bytes.toSlice(), 0)
    defer regular.destroy()
    let bold = expect Face.loadAt(bytes.toSlice(), 1)
    defer bold.destroy()

    Swag.require(regular.familyName == "Arial")
    Swag.require(bold.familyName == "Arial")
    Swag.require(not regular.isBold())
    Swag.require(bold.isBold())

    // A collection member is a whole face: its outlines resolve as usual.
    Swag.require(regular.glyphIndex('A') > 0)
    Swag.require(bold.glyphIndex('A') > 0)
}

// A large collection member survives changes to either the file or the caller's buffer.
#test
{
    var bytes = buildFontCollection(["arial.ttf", "arialbd.ttf"])
    Swag.require(bytes.count >= MinCollectionReadSize)
    let path = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("swag-collection-%.ttc", Guid128.random().toString()))
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path, bytes.toSlice())

    let snapshot = expect readFontFile(path, 1)
    Swag.require(snapshot.faceIndex == 0 and snapshot.bytes.count < bytes.count)
    let memorySnapshot = expect copyFontMember(bytes.toSlice(), 1)
    Swag.require(Slice.equals(snapshot.bytes.toSlice(), memorySnapshot.toSlice()))

    let original = loadFontBytes("arialbd.ttf")
    let expected = expect Face.load(original.toSlice())
    defer expected.destroy()
    let fileFace = expect Face.loadFile(path, 1)
    defer fileFace.destroy()
    let memoryFace = expect Face.loadAt(bytes.toSlice(), 1)
    defer memoryFace.destroy()

    discard expect File.writeAllBytes(path, BrokenFontBytes)
    bytes.fill(0)
    expect expected.setPixelSize(0, 18)
    expect expected.loadChar('A', .Render)
    for face in [fileFace, memoryFace]
    {
        Swag.require(face.isBold() and face.familyName == expected.familyName)
        Swag.require(face.glyphIndex('A') == expected.glyphIndex('A'))
        expect face.setPixelSize(0, 18)
        expect face.loadChar('A', .Render)
        Swag.require(face.glyph.advance.x == expected.glyph.advance.x)
        Swag.require(face.glyph.bitmap.rows == expected.glyph.bitmap.rows and face.glyph.bitmap.rows > 0)
        for row in face.glyph.bitmap.rows do
            Swag.require(Slice.equals(expect face.glyph.bitmap.row(row), expect expected.glyph.bitmap.row(row)))
    }
}

// A table range outside the file rejects only the member that references it.
#test
{
    var bytes     = buildFontCollection(["arial.ttf", "arialbd.ttf"])
    let directory = cast(u64, readBigU32(&bytes, 12))
    writeBigU32(&bytes, directory + 20, cast(u32, bytes.count) + 1)

    let path = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("swag-collection-%.ttc", Guid128.random().toString()))
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path, bytes.toSlice())

    var rejected: Swag.Error
    discard catch Face.loadFile(path) as rejected
    Swag.require(rejected.value() != null)
    let face = expect Face.loadFile(path, 1)
    defer face.destroy()
    Swag.require(face.isBold())
}

// Loading a collection without an index takes its first face.
#test
{
    let bytes = buildFontCollection(["arialbd.ttf", "arial.ttf"])

    let first = expect Face.load(bytes.toSlice())
    defer first.destroy()
    Swag.require(first.isBold())
}

// A collection is searchable by family without loading any of its faces, and the
// name each member answers is the one it carries once loaded.
#test
{
    let bytes = buildFontCollection(["arial.ttf", "segoeui.ttf"])

    Swag.require((expect Face.familyNameAt(bytes.toSlice(), 0)) == "Arial")
    Swag.require((expect Face.familyNameAt(bytes.toSlice(), 1)) == "Segoe UI")

    let second = expect Face.loadAt(bytes.toSlice(), 1)
    defer second.destroy()
    Swag.require(second.familyName == (expect Face.familyNameAt(bytes.toSlice(), 1)))
}

// A bare font file names its single face, and nothing beyond it.
#test
{
    let bytes = loadFontBytes("arial.ttf")
    Swag.require((expect Face.familyNameAt(bytes.toSlice(), 0)) == "Arial")

    var errBeyondOutcome: Swag.Error
    discard catch Face.familyNameAt(bytes.toSlice(), 1) as errBeyondOutcome
    let errBeyond = errBeyondOutcome.value()
    Swag.require(errBeyond != null)
}

// An index beyond the collection is reported rather than read out of bounds.
#test
{
    let bytes = buildFontCollection(["arial.ttf", "arialbd.ttf"])
    var errRangeOutcome: Swag.Error
    catch checkFaceLoadAt(bytes.toSlice(), 2) as errRangeOutcome
    let errRange = errRangeOutcome.value()
    Swag.require(errRange != null)
}

// A bare font file holds no face beyond the first.
#test
{
    let bytes = loadFontBytes("arial.ttf")
    var errSingleOutcome: Swag.Error
    catch checkFaceLoadAt(bytes.toSlice(), 1) as errSingleOutcome
    let errSingle = errSingleOutcome.value()
    Swag.require(errSingle != null)
}

// A WOFF container is rejected on sight, and counting its faces fails for the same
// reason loading it does.
#test
{
    var errWoffOutcome: Swag.Error
    catch checkFaceLoad(WoffBytes) as errWoffOutcome
    let errWoff = errWoffOutcome.value()
    Swag.require(errWoff != null)

    var errWoff2Outcome: Swag.Error
    catch checkFaceLoad(Woff2Bytes) as errWoff2Outcome
    let errWoff2 = errWoff2Outcome.value()
    Swag.require(errWoff2 != null)

    var errCountOutcome: Swag.Error
    discard catch Face.countFaces(WoffBytes) as errCountOutcome
    let errCount = errCountOutcome.value()
    Swag.require(errCount != null)
}

// An OpenType container is read, so an empty one fails on its missing tables rather than
// on its signature, and still counts as the one face its header declares.
#test
{
    var errCffOutcome: Swag.Error
    catch checkFaceLoad(OpenTypeCffBytes) as errCffOutcome
    let errCff = errCffOutcome.value()
    Swag.require(errCff != null)

    let count = expect Face.countFaces(OpenTypeCffBytes)
    Swag.require(count == 1)
}
