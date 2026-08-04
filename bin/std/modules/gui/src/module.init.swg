#global using Core

using Pixel

func nnFont(font: #null *Font)->*Font
{
    return font!
}

func nnPixels(pixels: #null [*] u8)->const *u8
{
    return cast(const *u8) pixels!
}
