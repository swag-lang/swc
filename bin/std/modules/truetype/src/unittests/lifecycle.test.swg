#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func assertFixtureFontLoads(fileName: string, expectedStyle: StyleFlag)
{
    var scope: FaceScope
    scope.init(fileName)
    let face = notnull scope.face

    @assert(scope.bytes.count > 0)
    @assert(face.glyphCount > 0)
    @assert(!face.familyName.isEmpty())
    @assert(!face.styleName.isEmpty())
    @assert((face.style & (.Bold | .Italic)) == expectedStyle)

    let glyphA = face.glyphIndex('A')
    @assert(glyphA > 0)

    discard expect face.setPixelSize(0, 18)
    discard expect face.loadGlyph(glyphA, .Render)
    @assert(face.glyph.bitmap.width > 0)
    @assert(face.glyph.bitmap.rows > 0)
    @assert(countBitmapCoverage(&face.glyph.bitmap) > 0)
}

#test
{
    let badFace0: #null *Face = catch Face.load(BrokenFontBytes) as err3
    @assert(err3 != null)

    var empty:    Array'u8
    let badFace1: #null *Face = catch Face.load(empty.toSlice()) as err4
    @assert(err4 != null)
}

#test
{
    var scope: FaceScope
    scope.init()
    let face = notnull scope.face

    @assert(scope.bytes.count > 0)
    @assert(face.glyphCount > 0)
    @assert(!face.familyName.isEmpty())
    @assert(!face.styleName.isEmpty())
    @assert(face.unitsPerEm > 0)
    @assert(face.ascender > 0)
    @assert(face.descender < 0)
    @assert(face.maxAdvanceWidth > 0)

    discard expect face.setPixelSize(0, 16)
    @assert(face.size.metrics.xPpem == 16)
    @assert(face.size.metrics.yPpem == 16)
    @assert(face.size.metrics.ascender > 0)
    @assert(face.size.metrics.descender < 0)
    @assert(face.size.metrics.maxAdvance > 0)

    discard expect face.setPixelSize(24, 0)
    @assert(face.size.metrics.xPpem == 24)
    @assert(face.size.metrics.yPpem == 24)

    discard catch face.setPixelSize(0, 0) as err8
    @assert(err8 != null)

    discard catch face.setPixelSize(Swag.U16.Max + 1, 16) as err9
    @assert(err9 != null)

    @assert(face.hasChar('A'))
    @assert(!face.hasChar(0x10FFFF))
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
    let context           = @getcontext()
    let originalAllocator = notnull context.allocator

    var scratchA: ScratchAllocator
    var scratchB: ScratchAllocator
    scratchA.setCapacity(4 * 1024 * 1024, originalAllocator)
    scratchB.setCapacity(4 * 1024 * 1024, originalAllocator)
    defer scratchA.release()
    defer scratchB.release()
    defer context.allocator = originalAllocator

    let bytes                  = loadFontBytes()
    let allocatorA: IAllocator = &scratchA
    let allocatorB: IAllocator = &scratchB
    context.allocator = allocatorA

    let face = expect Face.load(bytes.toSlice(), allocatorA)
    @assert(face != null)

    context.allocator = allocatorB
    face!.destroy()
}
