#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// An application can select the CPU backend before its first surface; creation then follows the
// normal GUI lifecycle without allocating a native window or replacing that backend with OpenGL.
#test
{
    var cpu: RenderCpu
    var app: Application
    app.setRenderer(&cpu)

    let surface = (expect app.createSurface(0, 0, 160, 96))!
    @assert(!app.renderer.needsNativeWindow())
    @assert(!surface.hWnd)

    surface.show()
    let image = app.renderer.readRenderTarget(&surface.rt, 0, 0, surface.rc.width, surface.rc.height)
    @assert(image.isValid() and image.width == surface.rc.width and image.height == surface.rc.height)
}

// The headless host must exercise the complete GUI paint path, not only record commands.
#test
{
    var host: Testing.HeadlessHost
    host.setup(96, 64)
    defer host.shutdown()
    let background = host.render()
    @assert(background.isValid())
    @assert(background.width == 96 and background.height == 64)
    @assert(background.pixelFormat == .BGRA8)

    let button  = PushButton.create(&host.root, "", {20, 16, 56, 32})
    let enabled = host.render()
    @assert(Memory.compare(enabled.pixels.buffer, background.pixels.buffer, enabled.byteCount) != 0)
    Pixel.Testing.assertImageGolden(&enabled, "widget.cpu.pushbutton")

    button.disable()
    let disabled = host.render()
    @assert(Memory.compare(disabled.pixels.buffer, enabled.pixels.buffer, disabled.byteCount) != 0)
}
