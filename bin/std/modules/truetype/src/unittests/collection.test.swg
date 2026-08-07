#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// A bare font file is a collection holding one face.
#test
{
    let bytes = loadFontBytes("arial.ttf")
    let count = expect Face.countFaces(bytes.toSlice())
    @assert(count == 1)

    let face = (expect Face.loadAt(bytes.toSlice(), 0))!
    defer face.destroy()
    @assert(face.familyName == "Arial")
}

// Every face of a collection loads independently, and the index selects which one.
#test
{
    let bytes = buildFontCollection(["arial.ttf", "arialbd.ttf"])
    let count = expect Face.countFaces(bytes.toSlice())
    @assert(count == 2)

    let regular = (expect Face.loadAt(bytes.toSlice(), 0))!
    defer regular.destroy()
    let bold = (expect Face.loadAt(bytes.toSlice(), 1))!
    defer bold.destroy()

    @assert(regular.familyName == "Arial")
    @assert(bold.familyName == "Arial")
    @assert(!regular.isBold())
    @assert(bold.isBold())

    // A collection member is a whole face: its outlines resolve as usual.
    @assert(regular.glyphIndex('A') > 0)
    @assert(bold.glyphIndex('A') > 0)
}

// Loading a collection without an index takes its first face.
#test
{
    let bytes = buildFontCollection(["arialbd.ttf", "arial.ttf"])

    let first = (expect Face.load(bytes.toSlice()))!
    defer first.destroy()
    @assert(first.isBold())
}

// A collection is searchable by family without loading any of its faces, and the
// name each member answers is the one it carries once loaded.
#test
{
    let bytes = buildFontCollection(["arial.ttf", "segoeui.ttf"])

    @assert((expect Face.familyNameAt(bytes.toSlice(), 0)) == "Arial")
    @assert((expect Face.familyNameAt(bytes.toSlice(), 1)) == "Segoe UI")

    let second = (expect Face.loadAt(bytes.toSlice(), 1))!
    defer second.destroy()
    @assert(second.familyName == (expect Face.familyNameAt(bytes.toSlice(), 1)))
}

// A bare font file names its single face, and nothing beyond it.
#test
{
    let bytes = loadFontBytes("arial.ttf")
    @assert((expect Face.familyNameAt(bytes.toSlice(), 0)) == "Arial")

    discard catch Face.familyNameAt(bytes.toSlice(), 1) as errBeyond
    @assert(errBeyond != null)
}

// An index beyond the collection is reported rather than read out of bounds.
#test
{
    let bytes    = buildFontCollection(["arial.ttf", "arialbd.ttf"])
    let outOfEnd = catch Face.loadAt(bytes.toSlice(), 2) as errRange
    @assert(errRange != null)
    @assert(outOfEnd == null)
}

// A bare font file holds no face beyond the first.
#test
{
    let bytes    = loadFontBytes("arial.ttf")
    let outOfEnd = catch Face.loadAt(bytes.toSlice(), 1) as errSingle
    @assert(errSingle != null)
    @assert(outOfEnd == null)
}

// Containers this module recognizes but cannot read are rejected on sight, and
// counting their faces fails for the same reason loading them does.
#test
{
    let cff = catch Face.load(OpenTypeCffBytes) as errCff
    @assert(errCff != null)
    @assert(cff == null)

    let woff = catch Face.load(WoffBytes) as errWoff
    @assert(errWoff != null)
    @assert(woff == null)

    let woff2 = catch Face.load(Woff2Bytes) as errWoff2
    @assert(errWoff2 != null)
    @assert(woff2 == null)

    discard catch Face.countFaces(OpenTypeCffBytes) as errCount
    @assert(errCount != null)
}
