#global using Core

using Pixel

func nnFont(font: *Font?)->*Font
{
    return font!
}

// Y of the top edge of `size` placed level with a line box of `family` centered on `centerY`.
//
// Every glyph a widget sets beside a word centered that way goes through this: an icon, a check
// mark, a drop-down arrow. Centering them on the cell instead leaves them off the word by the
// difference between the middle of the line box and the middle of the capitals, which belongs to
// the face. See [[Pixel.Font.opticalOffset]]. A family without a regular face falls back to the
// plain center, which is all that can be said without metrics.
//
// A widget that centers its line on the capitals — a field, a cell, anything with a frame the
// reader sees — needs no offset at all: see [[Pixel.Font.opticalLineTop]] and center the glyph on
// the same point.
func opticalTop(family: const *FontFamily?, centerY, size: f32)->f32
{
    if !family do
        return centerY - size * 0.5
    let font = family.getFont(.Regular)
    if !font do
        return centerY - size * 0.5
    return font.opticalTop(centerY, size)
}

func nnPixels(pixels: [*] u8?)->const *u8
{
    return cast(const *u8) pixels!
}
