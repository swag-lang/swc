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
