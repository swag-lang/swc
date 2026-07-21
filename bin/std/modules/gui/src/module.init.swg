#global using Core

using Pixel

func nnFont(font: #null *Font)->*Font
{
    return assume font
}

func nnPixels(pixels: #null [*] u8)->const *u8
{
    return cast(const *u8) (assume pixels)
}

func createGuiTypeFace(outFace: **TypeFace, name: string, bytes: const [..] u8) throw
{
    dref outFace = try TypeFace.create(name, bytes)
}
