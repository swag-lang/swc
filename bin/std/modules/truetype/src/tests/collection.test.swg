#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// A bare font file is a collection holding one face.
#test
{
    let bytes = loadFontBytes("arial.ttf")
    let count = expect Face.countFaces(bytes.toSlice())
    Swag.assert(count == 1)

    let face = (expect Face.loadAt(bytes.toSlice(), 0))!
    defer face.destroy()
    Swag.assert(face.familyName == "Arial")
}

// Every face of a collection loads independently, and the index selects which one.
#test
{
    let bytes = buildFontCollection(["arial.ttf", "arialbd.ttf"])
    let count = expect Face.countFaces(bytes.toSlice())
    Swag.assert(count == 2)

    let regular = (expect Face.loadAt(bytes.toSlice(), 0))!
    defer regular.destroy()
    let bold = (expect Face.loadAt(bytes.toSlice(), 1))!
    defer bold.destroy()

    Swag.assert(regular.familyName == "Arial")
    Swag.assert(bold.familyName == "Arial")
    Swag.assert(!regular.isBold())
    Swag.assert(bold.isBold())

    // A collection member is a whole face: its outlines resolve as usual.
    Swag.assert(regular.glyphIndex('A') > 0)
    Swag.assert(bold.glyphIndex('A') > 0)
}

// Loading a collection without an index takes its first face.
#test
{
    let bytes = buildFontCollection(["arialbd.ttf", "arial.ttf"])

    let first = (expect Face.load(bytes.toSlice()))!
    defer first.destroy()
    Swag.assert(first.isBold())
}

// A collection is searchable by family without loading any of its faces, and the
// name each member answers is the one it carries once loaded.
#test
{
    let bytes = buildFontCollection(["arial.ttf", "segoeui.ttf"])

    Swag.assert((expect Face.familyNameAt(bytes.toSlice(), 0)) == "Arial")
    Swag.assert((expect Face.familyNameAt(bytes.toSlice(), 1)) == "Segoe UI")

    let second = (expect Face.loadAt(bytes.toSlice(), 1))!
    defer second.destroy()
    Swag.assert(second.familyName == (expect Face.familyNameAt(bytes.toSlice(), 1)))
}

// A bare font file names its single face, and nothing beyond it.
#test
{
    let bytes = loadFontBytes("arial.ttf")
    Swag.assert((expect Face.familyNameAt(bytes.toSlice(), 0)) == "Arial")

    discard catch Face.familyNameAt(bytes.toSlice(), 1) as errBeyond
    Swag.assert(errBeyond != null)
}

// An index beyond the collection is reported rather than read out of bounds.
#test
{
    let bytes    = buildFontCollection(["arial.ttf", "arialbd.ttf"])
    let outOfEnd = catch Face.loadAt(bytes.toSlice(), 2) as errRange
    Swag.assert(errRange != null)
    Swag.assert(outOfEnd == null)
}

// A bare font file holds no face beyond the first.
#test
{
    let bytes    = loadFontBytes("arial.ttf")
    let outOfEnd = catch Face.loadAt(bytes.toSlice(), 1) as errSingle
    Swag.assert(errSingle != null)
    Swag.assert(outOfEnd == null)
}

// A WOFF container is rejected on sight, and counting its faces fails for the same
// reason loading it does.
#test
{
    let woff = catch Face.load(WoffBytes) as errWoff
    Swag.assert(errWoff != null)
    Swag.assert(woff == null)

    let woff2 = catch Face.load(Woff2Bytes) as errWoff2
    Swag.assert(errWoff2 != null)
    Swag.assert(woff2 == null)

    discard catch Face.countFaces(WoffBytes) as errCount
    Swag.assert(errCount != null)
}

// An OpenType container is read, so an empty one fails on its missing tables rather than
// on its signature, and still counts as the one face its header declares.
#test
{
    let cff = catch Face.load(OpenTypeCffBytes) as errCff
    Swag.assert(errCff != null)
    Swag.assert(cff == null)

    let count = expect Face.countFaces(OpenTypeCffBytes)
    Swag.assert(count == 1)
}
