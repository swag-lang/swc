#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// TrueType post format 2 maps Macintosh standard names and font-specific Pascal strings.
#test
{
    let bytes = loadFontBytes("arial.ttf")
    let font = expect buildPostFormat2Font(bytes.toSlice(), 36, 36, 200, 258, ["CustomGlyph"])
    let face = expect Face.load(font.toSlice())
    defer face.destroy()

    Swag.require(face.glyphIndexByName("A") == 36)
    Swag.require(face.glyphIndexByName("CustomGlyph") == 200)
    Swag.require(face.glyphIndexByName("MissingGlyph") == 0)
}

// Duplicate names preserve the first glyph index, matching the CFF and Type 1 maps.
#test
{
    let bytes = loadFontBytes("arial.ttf")
    let font = expect buildPostFormat2Font(bytes.toSlice(), 200, 258, 201, 259, ["Repeated", "Repeated"])
    let face = expect Face.load(font.toSlice())
    defer face.destroy()

    Swag.require(face.glyphIndexByName("Repeated") == 200)
}

// Custom name indices without their complete Pascal-string payload are rejected.
#test
{
    let bytes = loadFontBytes("arial.ttf")
    let font = expect buildPostFormat2Font(bytes.toSlice(), 200, 258, 201, 259, ["OnlyOne"], true)
    var rejected: Swag.Error
    discard catch Face.load(font.toSlice()) as rejected
    Swag.require(rejected.value() != null)
}

// Format 2.5 offsets address the same Macintosh standard glyph names.
#test
{
    let bytes = loadFontBytes("arial.ttf")
    let font = expect buildPostFormat25Font(bytes.toSlice(), 36, 36)
    let face = expect Face.load(font.toSlice())
    defer face.destroy()

    Swag.require(face.glyphIndexByName("A") == 36)
}

// Format 1 gives each glyph its position in the Macintosh standard order.
#test
{
    let bytes = loadFontBytes("arial.ttf")
    let font = expect buildPostFormat1Font(bytes.toSlice())
    let face = expect Face.load(font.toSlice())
    defer face.destroy()

    Swag.require(face.glyphIndexByName("A") == 36)
}

// Format 3 carries no glyph names.
#test
{
    let bytes = loadFontBytes("arial.ttf")
    let font = expect buildPostFormat3Font(bytes.toSlice())
    let face = expect Face.load(font.toSlice())
    defer face.destroy()

    Swag.require(face.glyphIndexByName("A") == 0)
}

// A post table shorter than its fixed header is rejected even for format 3.
#test
{
    let bytes = loadFontBytes("arial.ttf")
    var font = expect buildPostFormat3Font(bytes.toSlice())
    truncatePostTable(&font, 11)
    var rejected: Swag.Error
    discard catch Face.load(font.toSlice()) as rejected
    Swag.require(rejected.value() != null)
}
