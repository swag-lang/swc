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
    Swag.require(face.glyphName(36) == "A")
    Swag.require(face.glyphName(200) == "CustomGlyph")
    Swag.require(face.glyphName(face.glyphCount) == null)
}

// Duplicate names preserve the first glyph index, matching the CFF and Type 1 maps.
#test
{
    let bytes = loadFontBytes("arial.ttf")
    let font = expect buildPostFormat2Font(bytes.toSlice(), 200, 258, 201, 259, ["Repeated", "Repeated"])
    let face = expect Face.load(font.toSlice())
    defer face.destroy()

    Swag.require(face.glyphIndexByName("Repeated") == 200)
    Swag.require(face.glyphName(200) == "Repeated")
    Swag.require(face.glyphName(201) == "Repeated")
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
    Swag.require(face.glyphName(36) == "A")
}

// Format 1 gives each glyph its position in the Macintosh standard order.
#test
{
    let bytes = loadFontBytes("arial.ttf")
    let font = expect buildPostFormat1Font(bytes.toSlice())
    let face = expect Face.load(font.toSlice())
    defer face.destroy()

    Swag.require(face.glyphIndexByName("A") == 36)
    Swag.require(face.glyphName(36) == "A")
}

// Format 3 carries no glyph names.
#test
{
    let bytes = loadFontBytes("arial.ttf")
    let font = expect buildPostFormat3Font(bytes.toSlice())
    let face = expect Face.load(font.toSlice())
    defer face.destroy()

    Swag.require(face.glyphIndexByName("A") == 0)
    Swag.require(face.glyphName(0) == null)
}

// CFF and Type 1 names borrow the corresponding name already owned by their font data.
#test
{
    var cffFace: FaceImpl
    cffFace.face.setGlyphCount(3)
    cffFace.outlineSource = .Cff
    cffFace.cff.glyphNames.add(String.from(".notdef"))
    cffFace.cff.glyphNames.add(String.from("fi"))
    cffFace.cff.glyphNames.add(String.from(null))
    Swag.require(cffFace.face.glyphName(0) == ".notdef")
    Swag.require(cffFace.face.glyphName(1) == "fi")
    Swag.require(cffFace.face.glyphName(2) == null)
    Swag.require(cffFace.face.glyphName(3) == null)

    var type1Face: FaceImpl
    type1Face.face.setGlyphCount(2)
    type1Face.outlineSource = .Type1
    type1Face.type1.glyphNames.add(String.from(".notdef"))
    type1Face.type1.glyphNames.add(String.from("Aacute"))
    Swag.require(type1Face.face.glyphName(0) == ".notdef")
    Swag.require(type1Face.face.glyphName(1) == "Aacute")
    Swag.require(type1Face.face.glyphName(2) == null)
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
