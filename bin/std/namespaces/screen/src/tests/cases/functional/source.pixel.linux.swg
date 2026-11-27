#global if #os == Swag.TargetOs.Linux and #command == Swag.CompilerCommand.Test
#global private

// X11 pixel decoding preserves byte order and rounds TrueColor channels to the nearest byte.
#test
{
    let pixel: [4]u8 = [0x12, 0x34, 0x56, 0x78]
    Swag.require(x11Pixel(&pixel[0], 0, 2, 0) == 0x3412)
    Swag.require(x11Pixel(&pixel[0], 0, 2, 1) == 0x1234)
    Swag.require(x11Pixel(&pixel[0], 0, 3, 0) == 0x563412)
    Swag.require(x11Pixel(&pixel[0], 0, 3, 1) == 0x123456)
    Swag.require(x11Pixel(&pixel[0], 0, 4, 0) == 0x78563412)
    Swag.require(x11Pixel(&pixel[0], 0, 4, 1) == 0x12345678)

    Swag.require(x11Channel(0x00800000, 0x00F80000) == 132)
    Swag.require(x11Channel(0x00008000, 0x0000FC00) == 130)
    Swag.require(x11Channel(0x00000080, 0x000000FF) == 128)
    Swag.require(x11Channel(0x00F80000, 0x00F80000) == 255)
    Swag.require(x11Channel(0, 0x0000FC00) == 0)
}
