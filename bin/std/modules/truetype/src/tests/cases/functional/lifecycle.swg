#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func assertFixtureFontLoads(fileName: string, expectedStyle: StyleFlag)
{
    var faceScope: FaceScope
    faceScope.init(fileName)
    let face = unwrap faceScope.face

    Swag.require(not faceScope.bytes.isEmpty())
    Swag.require(face.glyphCount > 0)
    Swag.require(not face.familyName.isEmpty())
    Swag.require(not face.styleName.isEmpty())
    Swag.require((face.style & (.Bold | .Italic)) == expectedStyle)

    let glyphA = face.glyphIndex('A')
    Swag.require(glyphA > 0)

    discard expect face.setPixelSize(0, 18)
    discard expect face.loadGlyph(glyphA, .Render)
    Swag.require(face.glyph.bitmap.width > 0)
    Swag.require(face.glyph.bitmap.rows > 0)
    Swag.require(countBitmapCoverage(&face.glyph.bitmap) > 0)
}

#test
{
    var err3Outcome: Swag.Error
    catch checkFaceLoad(BrokenFontBytes) as err3Outcome
    let err3 = err3Outcome.value()
    Swag.require(err3 != null)

    var empty:       Array'u8
    var err4Outcome: Swag.Error
    catch checkFaceLoad(empty.toSlice()) as err4Outcome
    let err4 = err4Outcome.value()
    Swag.require(err4 != null)
}

#test
{
    var faceScope: FaceScope
    faceScope.init()
    let face = unwrap faceScope.face

    Swag.require(not faceScope.bytes.isEmpty())
    Swag.require(face.glyphCount > 0)
    Swag.require(not face.familyName.isEmpty())
    Swag.require(not face.styleName.isEmpty())
    Swag.require(face.unitsPerEm > 0)
    Swag.require(face.ascender > 0)
    Swag.require(face.descender < 0)
    Swag.require(face.maxAdvanceWidth > 0)

    discard expect face.setPixelSize(0, 16)
    Swag.require(face.size.metrics.xPpem == 16)
    Swag.require(face.size.metrics.yPpem == 16)
    Swag.require(face.size.metrics.ascender > 0)
    Swag.require(face.size.metrics.descender < 0)
    Swag.require(face.size.metrics.maxAdvance > 0)

    discard expect face.setPixelSize(24, 0)
    Swag.require(face.size.metrics.xPpem == 24)
    Swag.require(face.size.metrics.yPpem == 24)

    var err8Outcome: Swag.Error
    discard catch face.setPixelSize(0, 0) as err8Outcome
    let err8 = err8Outcome.value()
    Swag.require(err8 != null)

    var err9Outcome: Swag.Error
    discard catch face.setPixelSize(Swag.U16.Max + 1, 16) as err9Outcome
    let err9 = err9Outcome.value()
    Swag.require(err9 != null)

    Swag.require(face.hasChar('A'))
    Swag.require(not face.hasChar(0x10FFFF))
}

#test
{
    var faceData: FaceImpl
    var face = &faceData.face
    face.setHeader(16, 0, 0, 0, 0)
    face.setHorizontalMetrics(16000, -100, -15900, 16000)
    face.initializeRecords()

    discard expect face.setPixelSize(4095, 4095)
    Swag.require(face.size.metrics.xScale > 0)
    Swag.require(face.size.metrics.ascender > 0)

    var oversizedSizeOutcome: Swag.Error
    discard catch face.setPixelSize(65535, 65535) as oversizedSizeOutcome
    Swag.require(oversizedSizeOutcome.value() != null)
    Swag.require(face.size.metrics.xPpem == 4095)
}

#test
{
    assertFixtureFontLoads("arial.ttf", .None)
    assertFixtureFontLoads("arialbd.ttf", .Bold)
    assertFixtureFontLoads("ariali.ttf", .Italic)
    assertFixtureFontLoads("arialbi.ttf", .Bold | .Italic)
}

// A face retains the allocator that owns its outer allocation. Destroying it after
// the thread context switches allocators must not route the pointer to the new one.
#test
{
    let context = Swag.getContext()
    let originalAllocator = unwrap context.allocator

    var scratchA: ScratchAllocator
    var scratchB: ScratchAllocator
    scratchA.setCapacity(4 * 1024 * 1024, originalAllocator)
    scratchB.setCapacity(4 * 1024 * 1024, originalAllocator)
    defer scratchA.release()
    defer scratchB.release()
    defer context.allocator = originalAllocator

    let bytes = loadFontBytes()
    let allocatorA: IAllocator = &scratchA
    let allocatorB: IAllocator = &scratchB
    context.allocator = allocatorA

    let face = expect Face.load(bytes.toSlice(), allocatorA)
    #assert(#typeof(face) == *Face)

    context.allocator = allocatorB
    face.destroy()
}

// A face's nested storage follows its explicit allocator, and destroy releases every block.
#test
{
    var bytes = loadFontBytes()
    var faceAllocator:    Swag.Allocator
    var contextAllocator: Swag.Allocator
    faceAllocator.setup()
    contextAllocator.setup()
    defer faceAllocator.releaseAll()
    defer contextAllocator.releaseAll()

    let context = Swag.getContext()
    let previousAllocator = context.allocator
    defer context.allocator = previousAllocator
    let contextAllocatorView: IAllocator = &contextAllocator
    let faceAllocatorView:    IAllocator = &faceAllocator
    context.allocator = contextAllocatorView

    let faceBaseline    = faceAllocator.stats().countAlloc
    let contextBaseline = contextAllocator.stats().countAlloc
    let face = expect Face.load(bytes.toSlice(), faceAllocatorView)
    let loadedAllocations = faceAllocator.stats().countAlloc
    Swag.require(contextAllocator.stats().countAlloc == contextBaseline)
    Swag.require(loadedAllocations > faceBaseline)
    face.destroy()
    Swag.require(faceAllocator.stats().countAlloc < loadedAllocations)
}
