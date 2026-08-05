#global using Core

using Pixel

func nnFont(font: #null *Font)->*Font
{
    return font!
}

// Y of the top edge of `size` placed level with a line of `family` centered on `centerY`.
//
// Every glyph a widget sets beside a word goes through this: an icon, a check mark, a
// drop-down arrow. Centering them on the cell instead drops them below the word, because a
// line box reaches down to the descenders while the word is read on its capitals. See
// [[Pixel.Font.opticalOffset]]. A family without a regular face falls back to the plain
// center, which is all that can be said without metrics.
func opticalTop(family: #null const *FontFamily, centerY, size: f32)->f32
{
    if !family do
        return centerY - size * 0.5
    let font = family.getFont(.Regular)
    if !font do
        return centerY - size * 0.5
    return font.opticalTop(centerY, size)
}

func nnPixels(pixels: #null [*] u8)->const *u8
{
    return cast(const *u8) pixels!
}
