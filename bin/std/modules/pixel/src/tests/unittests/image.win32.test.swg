#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Swag, Win32

// Native icon conversion keeps RGBA source colors after Win32's BGRA boundary.
#test
{
    var source = Image.create(2, 1, .RGBA8)
    let pixels = source.pixels.buffer!
    pixels[0] = 0xF7
    pixels[1] = 0xF9
    pixels[2] = 0x00
    pixels[3] = 0xFF
    pixels[4] = 0x0B
    pixels[5] = 0x0B
    pixels[6] = 0x0D
    pixels[7] = 0xFF

    let icon = expect source.toHicon()
    defer discard catch DestroyIcon(icon)

    let roundTrip = expect Image.from(icon)
    @assert(roundTrip.pixelFormat == .BGRA8)
    let result = roundTrip.pixels.buffer!
    @assert(result[0] == 0x00 and result[1] == 0xF9 and result[2] == 0xF7 and result[3] == 0xFF)
    @assert(result[4] == 0x0D and result[5] == 0x0B and result[6] == 0x0B and result[7] == 0xFF)
}
