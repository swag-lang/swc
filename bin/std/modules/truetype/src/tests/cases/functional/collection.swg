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

// Copies and loaded faces keep the snapshot alive through the last owner.
#test
{
    var bytes = buildFontCollection(["arial.ttf", "arialbd.ttf"])
    var allocator: Swag.Allocator
    allocator.setup()
    defer allocator.releaseAll()
    let allocationView: IAllocator = &allocator
    let baseline = allocator.stats().countAlloc

    var source   = FontSource.copy(bytes.toSlice(), allocationView)
    var retained = source
    let regular  = expect source.loadFace()
    source = {}
    bytes.fill(0)

    var badIndex: Swag.Error
    discard catch retained.loadFace(2) as badIndex
    Swag.require(badIndex.value() != null)
    let bold          = expect retained.loadFace(1)
    let firstBacking  = cast(*FaceImpl, cast(*void, regular))
    let secondBacking = cast(*FaceImpl, cast(*void, bold))
    Swag.require(firstBacking.fontBytes().buffer == retained.bytes().buffer)
    Swag.require(secondBacking.fontBytes().buffer == retained.bytes().buffer)
    retained = {}
    Swag.require(allocator.stats().countAlloc > baseline)

    expect regular.setPixelSize(0, 13)
    expect bold.setPixelSize(0, 21)
    expect regular.loadChar('A', .Render)
    expect bold.loadChar('A', .Render)
    Swag.require(not regular.isBold() and bold.isBold())
    Swag.require(regular.glyph.bitmap.rows > 0 and bold.glyph.bitmap.rows > regular.glyph.bitmap.rows)

    regular.destroy()
    expect bold.loadChar('B', .Render)
    Swag.require(bold.glyph.bitmap.rows > 0)
    bold.destroy()
    Swag.require(allocator.stats().countAlloc == baseline)

    var empty:    FontSource
    var noSource: Swag.Error
    discard catch empty.loadFace() as noSource
    Swag.require(empty.bytes().count == 0 and noSource.value() != null)
}

// Separate workers can retain a common source and render independently.
#test
{
    let bytes  = buildFontCollection(["arial.ttf", "arialbd.ttf"])
    let source = FontSource.copy(bytes.toSlice())
    var ready:   u32
    var tasks:   [2] Swag.Task'bool
    var workers: [2] Swag.Executor
    for &task, index in tasks
    {
        workers[index].start()
        task.submit(func|source = &source, ready = &ready, index|()->bool
        {
            discard Atomic.add(ready, 1)
            while Atomic.get(ready) != 2 do
                Threading.Thread.yield()

            for 4
            {
                let face = expect source.loadFace(cast(u32, index))
                defer face.destroy()
                expect face.setPixelSize(0, 20)
                expect face.loadChar('A', .Render)
                if face.isBold() != (index == 1) or not face.glyph.bitmap.rows do
                    return false
            }

            return true
        },
                    executor: &workers[index])
    }

    for &task in tasks do
        Swag.require(expect task.take())
}

// A large collection member survives changes to either the file or the caller's buffer.
#test
{
    var bytes = buildFontCollection(["arial.ttf", "arialbd.ttf"])
    Swag.require(bytes.count >= MinFontCompactionSize)
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

    var source = expect FontSource.loadFile(path)
    discard expect File.writeAllBytes(path, BrokenFontBytes)
    bytes.fill(0)
    let sharedFace = expect source.loadFace(1)
    defer sharedFace.destroy()
    source = {}
    expect expected.setPixelSize(0, 18)
    expect expected.loadChar('A', .Render)
    for face in [fileFace, memoryFace, sharedFace]
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

// A standalone snapshot can omit glyph variations while validating their source range.
#test
{
    var bytes    = loadFontBytes("arial.ttf")
    let original = expect Face.load(bytes.toSlice())
    defer original.destroy()
    let record = parseTestTableRecord(&bytes, imageTag('D'u32, 'S'u32, 'I'u32, 'G'u32))
    let offset = bytes.count
    bytes.resize(offset + MinFontCompactionSize)
    writeBigU32(&bytes, record, imageTag('g'u32, 'v'u32, 'a'u32, 'r'u32))
    writeBigU32(&bytes, record + 8, cast(u32, offset))
    writeBigU32(&bytes, record + 12, cast(u32, MinFontCompactionSize))

    let path = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("swag-variable-%.ttf", Guid128.random().toString()))
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path, bytes.toSlice())

    let file   = expect readFontFile(path, 0)
    let memory = expect copyFontMember(bytes.toSlice(), 0)
    Swag.require(file.bytes.count <= offset and Slice.equals(file.bytes.toSlice(), memory.toSlice()))
    let face = expect Face.loadFile(path)
    defer face.destroy()
    expect original.setPixelSize(0, 18)
    expect face.setPixelSize(0, 18)
    expect original.loadChar('A', .Render)
    expect face.loadChar('A', .Render)
    Swag.require(face.glyph.advance.x == original.glyph.advance.x)
    Swag.require(face.glyph.bitmap.rows == original.glyph.bitmap.rows and face.glyph.bitmap.rows > 0)
    for row in face.glyph.bitmap.rows do
        Swag.require(Slice.equals(expect face.glyph.bitmap.row(row), expect original.glyph.bitmap.row(row)))

    writeBigU32(&bytes, record + 12, cast(u32, MinFontCompactionSize + 1))
    discard expect File.writeAllBytes(path, bytes.toSlice())
    var invalidFile:   Swag.Error
    var invalidMemory: Swag.Error
    discard catch Face.loadFile(path) as invalidFile
    discard catch Face.load(bytes.toSlice()) as invalidMemory
    Swag.require(invalidFile.value() != null and invalidMemory.value() != null)
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
