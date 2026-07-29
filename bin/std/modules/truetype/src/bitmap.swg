using Swag, Core

// Identifies the storage layout of a rendered [[TrueType.Bitmap]].
public enum PixelMode
{
    Gray // One byte represents each grayscale or SDF pixel.
    Rgba // Four bytes represent the RGB multi-channel field and alpha distance.
}

// Describes the borrowed pixels produced for the current glyph.
//
// The buffer belongs to the parent [[TrueType.Face]]. Its address and contents
// may change after another load or render operation, and become invalid when the
// face is destroyed. Walk rows by `pitch` bytes rather than deriving a stride
// from `width`.
public struct Bitmap
{
    rows:      u32          // Number of pixel rows.
    width:     u32          // Number of pixels in each row.
    pitch:     s32          // Byte distance between consecutive rows.
    buffer:    #null [*] u8 // Borrowed address of the first pixel, or null when empty.
    grayCount: u16          // Number of representable coverage levels.
    pixelMode: PixelMode    // Encoding used by `buffer`.
}
