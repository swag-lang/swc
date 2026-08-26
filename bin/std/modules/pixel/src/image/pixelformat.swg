#global public

using Swag

// Describes the channel set, the byte order and the storage class of an 8-bit picture.
//
// Every format but one packs its channels into consecutive bytes of one row. `Yuv420` does not:
// it is what a video codec reconstructs, and it stores luma at full resolution beside two chroma
// planes at half resolution on both axes, so one chroma sample serves a two-by-two block. Ask
// [[Pixel.PixelFormat.isPacked]] before treating a format as bytes per pixel; [[Pixel.Image]]
// holds packed formats only, and a planar picture is described by [[Pixel.Yuv420View]].
enum PixelFormat: u8
{
    BGR8      // Blue, green, then red; 24 bits per pixel.
    BGRA8     // Blue, green, red, then alpha; 32 bits per pixel.
    RGB8      // Red, green, then blue; 24 bits per pixel.
    RGBA8     // Red, green, blue, then alpha; 32 bits per pixel.

    // Planar 4:2:0 luma and chroma in the studio range, the layout a video codec produces.
    // Twelve bits per pixel on average, and not one pixel's worth of consecutive bytes.
    Yuv420
}

impl PixelFormat
{
    // Reports whether one pixel occupies a whole number of consecutive bytes.
    //
    // Everything that walks a picture by [[Pixel.Image.bytesPerPixel]] and
    // [[Pixel.Image.rowStride]] needs this to hold. A planar format is carried by a texture and
    // by [[Pixel.Yuv420View]], never by an image.
    #[ConstExpr]
    func isPacked(me)->bool
    {
        switch #complete me
        {
        case .BGR8:   return true
        case .BGRA8:  return true
        case .RGB8:   return true
        case .RGBA8:  return true
        case .Yuv420: return false
        }

        return false
    }

    // Returns the number of bits one pixel occupies on average.
    //
    // A planar format answers its average, which is not the size of anything addressable: twelve
    // bits is what 4:2:0 costs per pixel over a whole picture.
    #[ConstExpr]
    func bitsPerPixel(me)->u8
    {
        switch #complete me
        {
        case .BGR8:   return 24
        case .BGRA8:  return 32
        case .RGB8:   return 24
        case .RGBA8:  return 32
        case .Yuv420: return 12
        }

        return 0
    }

    // Returns the number of stored color channels.
    #[ConstExpr]
    func channels(me)->u8
    {
        switch #complete me
        {
        case .BGR8:   return 3
        case .BGRA8:  return 4
        case .RGB8:   return 3
        case .RGBA8:  return 4
        case .Yuv420: return 3
        }

        return 0
    }

    // Returns the bit depth of each channel.
    #[ConstExpr]
    func bitDepth(me)->u8
    {
        switch #complete me
        {
        case .BGR8:   return 8
        case .BGRA8:  return 8
        case .RGB8:   return 8
        case .RGBA8:  return 8
        case .Yuv420: return 8
        }

        return 0
    }

    // Reports whether the format stores an alpha channel.
    #[ConstExpr]
    func hasAlpha(me)->bool
    {
        switch #complete me
        {
        case .BGR8:   return false
        case .BGRA8:  return true
        case .RGB8:   return false
        case .RGBA8:  return true
        case .Yuv420: return false
        }

        return false
    }
}
