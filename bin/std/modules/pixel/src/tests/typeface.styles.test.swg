#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    let bytes = makeTypeFaceCollection()
    let path  = makeTempImagePath(".ttc")
    discard expect File.writeAllBytes(path, bytes.toSlice())
    defer discard catch File.delete(path)
    let ordinary = expect TypeFace.loadAt(path, 0)
    let bold     = expect TypeFace.loadStyledAt(path, 0, .Bold)
    let italic   = expect TypeFace.loadStyledAt(path, 0, .Italic)
    let combined = expect TypeFace.loadStyledAt(path, 0, .BoldItalic)
    Swag.assert(ordinary != bold and bold != italic and combined != bold)
    Swag.assert(not ordinary.forceBold and not ordinary.forceItalic)
    Swag.assert(bold.forceBold and not bold.forceItalic)
    Swag.assert(not italic.forceBold and italic.forceItalic)
    Swag.assert(combined.forceBold and combined.forceItalic)
    let ownedPath = String.from(path.toString())
    Swag.assert((expect TypeFace.loadStyledAt(ownedPath, 0, .Bold)) == bold)
    Swag.assert((expect TypeFace.loadAt(path, 0)) == ordinary)
    let realBold = expect TypeFace.loadStyledAt(path, 1, .Bold)
    Swag.assert(realBold.isBold() and not realBold.forceBold)

    // Rasterizing a variant cannot overwrite the ordinary face's borrowed glyph workspace.
    let originalBitmap = expect ordinary.renderGlyph('A', 16)
    let width          = originalBitmap.width
    let height         = originalBitmap.rows
    discard expect combined.renderGlyph('W', 40)
    Swag.assert(originalBitmap.width == width and originalBitmap.rows == height)
    Swag.assert(not ordinary.forceBold and not ordinary.forceItalic)

    var outcome: Swag.Error
    discard catch TypeFace.loadStyledAt(path, 2, .Bold) as outcome
    Swag.assert(outcome.value() != null)
    Swag.assert((expect TypeFace.loadStyledAt(path, 0, .Bold)) == bold)
    discard expect File.delete(path)
    Swag.assert((expect TypeFace.loadStyledAt(path, 0, .Bold)) == bold)
}

#test
{
    var outcome: Swag.Error
    discard catch FontFamily.createTypeFace("Missing family", cast(FontFamilyStyle, 255)) as outcome
    Swag.assert(outcome.value() is Errors.BadParameterError)
}
