#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func assertFixtureFontLoads(fileName: string, expectedStyle: StyleFlag)
{
    var scope: FaceScope
    scope.init(fileName)
    let face = scope.face!

    Swag.assert(scope.bytes.count > 0)
    Swag.assert(face.glyphCount > 0)
    Swag.assert(!face.familyName.isEmpty())
    Swag.assert(!face.styleName.isEmpty())
    Swag.assert((face.style & (.Bold | .Italic)) == expectedStyle)

    let glyphA = face.glyphIndex('A')
    Swag.assert(glyphA > 0)

    discard expect face.setPixelSize(0, 18)
    discard expect face.loadGlyph(glyphA, .Render)
    Swag.assert(face.glyph.bitmap.width > 0)
    Swag.assert(face.glyph.bitmap.rows > 0)
    Swag.assert(countBitmapCoverage(&face.glyph.bitmap) > 0)
}

#test
{
    let badFace0: *Face? = catch Face.load(BrokenFontBytes) as err3
    Swag.assert(err3 != null)

    var empty:    Array'u8
    let badFace1: *Face? = catch Face.load(empty.toSlice()) as err4
    Swag.assert(err4 != null)
}

#test
{
    var scope: FaceScope
    scope.init()
    let face = scope.face!

    Swag.assert(scope.bytes.count > 0)
    Swag.assert(face.glyphCount > 0)
    Swag.assert(!face.familyName.isEmpty())
    Swag.assert(!face.styleName.isEmpty())
    Swag.assert(face.unitsPerEm > 0)
    Swag.assert(face.ascender > 0)
    Swag.assert(face.descender < 0)
    Swag.assert(face.maxAdvanceWidth > 0)

    discard expect face.setPixelSize(0, 16)
    Swag.assert(face.size.metrics.xPpem == 16)
    Swag.assert(face.size.metrics.yPpem == 16)
    Swag.assert(face.size.metrics.ascender > 0)
    Swag.assert(face.size.metrics.descender < 0)
    Swag.assert(face.size.metrics.maxAdvance > 0)

    discard expect face.setPixelSize(24, 0)
    Swag.assert(face.size.metrics.xPpem == 24)
    Swag.assert(face.size.metrics.yPpem == 24)

    discard catch face.setPixelSize(0, 0) as err8
    Swag.assert(err8 != null)

    discard catch face.setPixelSize(Swag.U16.Max + 1, 16) as err9
    Swag.assert(err9 != null)

    Swag.assert(face.hasChar('A'))
    Swag.assert(!face.hasChar(0x10FFFF))
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
    let context           = Swag.getContext()
    let originalAllocator = context.allocator!

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
    Swag.assert(face != null)

    context.allocator = allocatorB
    face!.destroy()
}
