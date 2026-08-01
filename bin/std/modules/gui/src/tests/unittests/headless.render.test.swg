#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// The headless host must exercise the complete GUI paint path, not only record commands.
#test
{
    var host: Testing.HeadlessHost
    host.setup(96, 64)

    let background = host.render()
    @assert(background.isValid())
    @assert(background.width == 96 and background.height == 64)
    @assert(background.pixelFormat == .BGRA8)

    let button = PushButton.create(&host.root, "", {20, 16, 56, 32})
    let enabled = host.render()
    @assert(Memory.compare(enabled.pixels.buffer, background.pixels.buffer, enabled.byteCount) != 0)
    Pixel.Testing.assertImageGolden(&enabled, "widget.cpu.pushbutton")

    button.disable()
    let disabled = host.render()
    @assert(Memory.compare(disabled.pixels.buffer, enabled.pixels.buffer, disabled.byteCount) != 0)
}
