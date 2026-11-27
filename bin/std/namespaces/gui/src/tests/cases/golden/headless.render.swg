#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// The headless host must exercise the complete GUI paint path, not only record commands.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(96, 64)

    let background = host.render()
    Swag.require(background.isValid())
    Swag.require(background.width == 96 and background.height == 64)
    Swag.require(background.pixelFormat == .BGRA8)

    let button  = PushButton.create(&host.root, "", {20, 16, 56, 32})
    let enabled = host.render()
    Swag.require(not Slice.equals(enabled.pixels.toSlice(), background.pixels.toSlice()))
    Pixel.Testing.assertImageGolden(&enabled, "widget.cpu.pushbutton")

    button.disable()
    let disabled = host.render()
    Swag.require(not Slice.equals(disabled.pixels.toSlice(), enabled.pixels.toSlice()))
}
