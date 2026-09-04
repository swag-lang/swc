using Swag, Core

// Identifies the storage layout of a rendered [[TrueType.Bitmap]].
public enum PixelMode
{
    Gray     // One byte represents each grayscale or SDF pixel.
    Rgba     // Four bytes represent the RGB multi-channel field and alpha distance.
}

public impl PixelMode
{
    // Returns the number of bytes occupied by one pixel in this mode.
    mtd bytesPerPixel()->u32
    {
        switch #complete me
        {
        case .Gray: return 1
        case .Rgba: return 4
        }
    }
}

impl Bitmap
{
    mtd reset()
    {
        .rows      = 0
        .width     = 0
        .pitch     = 0
        .buffer    = null
        .pixelMode = .Gray
        .grayCount = 256
    }

    mtd set(rows, width: u32, pitch: s32, buffer: [*] u8?, pixelMode: PixelMode)
    {
        .rows      = rows
        .width     = width
        .pitch     = pitch
        .buffer    = buffer
        .pixelMode = pixelMode
        .grayCount = 256
    }
}

// Describes the borrowed pixels produced for the current glyph.
//
// The buffer belongs to the parent [[TrueType.Face]]. Its address and contents
// may change after another load or render operation, and become invalid when the
// face is destroyed. Walk rows by `pitch` bytes rather than deriving a stride
// from `width`.
public struct Bitmap
{
    // Rendering establishes the bitmap as one result. Callers can read the view
    // but cannot replace its storage or make its geometry disagree with it.

    public readonly
    {
        rows:      u32           // Number of pixel rows.
        width:     u32           // Number of pixels in each row.
        pitch:     s32           // Byte distance between consecutive rows.
        buffer:    [*] u8?       // Borrowed address of the first pixel, or null when empty.
        grayCount: u16           // Number of representable coverage levels.
        pixelMode: PixelMode     // Encoding used by `buffer`.
    }
}
