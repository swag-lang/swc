#global #[Swag.ExplicitNullability]
#global using Core

using Pixel

func nnFont(font: #null *Font)->#nonull *Font
{
    Debug.assert(font != null)
    return font orelse cast(#nonull *Font) 1'u64
}

func nnPixels(pixels: #null [*] u8)->#nonull const *u8
{
    Debug.assert(pixels != null)
    return cast(#nonull const *u8) (pixels orelse cast(#nonull [*] u8) 1'u64)
}

func createGuiTypeFace(outFace: #nonull *#nonull *TypeFace, name: #nonull string, bytes: #nonull const [..] u8) throw
{
    dref outFace = try TypeFace.create(name, bytes)
}
