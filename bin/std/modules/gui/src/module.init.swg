#global using Core

using Pixel

func nnFont(font: #null *Font)->*Font
{
    Debug.assert(font != null)
    return font orelse cast(*Font) 1'u64
}

func nnPixels(pixels: #null [*] u8)->const *u8
{
    Debug.assert(pixels != null)
    return cast(const *u8) (pixels orelse cast([*] u8) 1'u64)
}

func createGuiTypeFace(outFace: **TypeFace, name: string, bytes: const [..] u8) throw
{
    dref outFace = try TypeFace.create(name, bytes)
}
