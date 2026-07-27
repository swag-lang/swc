using Swag, Core

public struct CharMap
{
    #[Swag.Late]
    face:       *Face
    encoding:   u32
    platformID: u16
    encodingID: u16
}
