#global if #command == Swag.CompilerCommand.Test

using Swag, Core

private func createNullableTypeFace(name: string, bytes: const [..] u8)->#null *TypeFace fail => try TypeFace.create(name, bytes)
private func renderNullableGlyph(face: *TypeFace)->#null const *Bitmap fail => try face.renderGlyph('A', 16, false)

// A rejected face must not try to destroy the uninitialized native face during failure cleanup.
#test
{
    const truncated: [4] u8 = [0, 1, 0, 0]
    let face = catch createNullableTypeFace("pixel-test-truncated-font", truncated) as loadError
    Swag.assert(loadError != null)
    Swag.assert(face == null)
}

// A typeface remains usable after its caller releases the source bytes: TrueType.Face owns the
// only retained copy, so the Pixel cache does not need to keep the complete font a second time.
#test
{
    var bytes = expect File.readAllBytes(getTestDataPath("segoeui.ttf"))
    let face  = expect createNullableTypeFace("pixel-test-owned-font-bytes", bytes.toSlice())!
    bytes.fill(0)
    bytes.free()

    Swag.assert((face.familyName()).count != 0)
    let bitmap = expect renderNullableGlyph(face)!
    Swag.assert(bitmap.width != 0)
}
