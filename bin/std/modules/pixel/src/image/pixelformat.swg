#global public

using Swag

// Describes the byte order and channel set of one tightly packed 8-bit pixel.
enum PixelFormat: u8
{
    BGR8      // Blue, green, then red; 24 bits per pixel.
    BGRA8     // Blue, green, red, then alpha; 32 bits per pixel.
    RGB8      // Red, green, then blue; 24 bits per pixel.
    RGBA8     // Red, green, blue, then alpha; 32 bits per pixel.
}

impl PixelFormat
{
    // Returns the number of bits occupied by one pixel.
    #[ConstExpr]
    func bpp(me)->u8
    {
        switch #complete me
        {
        case .BGR8:  return 24
        case .BGRA8: return 32
        case .RGB8:  return 24
        case .RGBA8: return 32
        }

        return 0
    }

    // Returns the number of stored color channels.
    #[ConstExpr]
    func channels(me)->u8
    {
        switch #complete me
        {
        case .BGR8:  return 3
        case .BGRA8: return 4
        case .RGB8:  return 3
        case .RGBA8: return 4
        }

        return 0
    }

    // Returns the bit depth of each channel.
    #[ConstExpr]
    func bitDepth(me)->u8
    {
        switch #complete me
        {
        case .BGR8:  return 8
        case .BGRA8: return 8
        case .RGB8:  return 8
        case .RGBA8: return 8
        }

        return 0
    }

    // Reports whether the format stores an alpha channel.
    #[ConstExpr]
    func hasAlpha(me)->bool
    {
        switch #complete me
        {
        case .BGR8:  return false
        case .BGRA8: return true
        case .RGB8:  return false
        case .RGBA8: return true
        }

        return false
    }
}
