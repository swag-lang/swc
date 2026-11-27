#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Glyph-name Unicode escapes accept scalar values and map invalid values to zero.
#test
{
    Swag.require(glyphNameRune("uni0041") == 'A')
    Swag.require(glyphNameRune("uD7FF") == cast(rune, 0xD7FF))
    Swag.require(glyphNameRune("uE000") == cast(rune, 0xE000))
    Swag.require(glyphNameRune("u10FFFF") == cast(rune, 0x10FFFF))

    Swag.require(glyphNameRune("uniD800") == 0)
    Swag.require(glyphNameRune("uDFFF") == 0)
    Swag.require(glyphNameRune("u110000") == 0)
}
