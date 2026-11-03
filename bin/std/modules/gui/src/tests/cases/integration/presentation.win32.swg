#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Pixel, Win32, Ogl

// Ordinary frames yield to input while readback is pending, coalesce dirty content, and never
// let an older asynchronous frame replace a synchronously prepared resize.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    var icon = Image.create(16, 16, .RGBA8)
    icon.clear()
    app.setAppIcon(#move icon)
    Swag.require(not app.appGlyph(16).isValid())
    let surface = expect app.createSurface(40, 40, 360, 240, surfaceId: "gui-async-presentation-test")
    Swag.require(app.appGlyph(16).isValid())
    let button = PushButton.create(surface.wnd.view, "Probe", {32, 32, 84, 32})
    surface.show()
    Swag.require(surface.presentationWidth == surface.rc.width)
    Swag.require(not surface.readback.isPending())
    Swag.require(not surface.presentationTarget.colorBuffer.isValid())

    app.rendererOgl.resetScratchCounters()
    surface.invalidate()
    surface.paint()
    Swag.require(surface.readback.isPending())

    // Border scratch stays on the perimeter, even when the whole window is repainted.
    Swag.require(app.rendererOgl.scratchClearedPixels < cast(u64, surface.rc.width) * cast(u64, surface.rc.height) / 2)
    surface.invalidate()
    var dispatched: bool
    surface.wnd.view.hookOnEvent = func|&dispatched|(_, evt)->bool
    {
        if evt is CommandEvent as command where command.id == "presentation.probe"
        {
            dispatched = true
            return true
        }

        return false
    }

    surface.wnd.view.postCommandEvent("presentation.probe")
    app.sendPostedEvents()
    Swag.require(dispatched and surface.isDirty and surface.readback.isPending())

    var watch: Time.Stopwatch
    watch.start()
    while surface.readback.isPending() and watch.elapsedMilliseconds() < 2000
    {
        discard surface.advanceNativePresentation()
        Threading.Thread.sleep(1'ms)
    }

    Swag.require(not surface.readback.isPending() and not surface.asynchronousPresentationFailed)
    Swag.require(surface.isDirty)
    surface.paint()
    Swag.require(surface.readback.isPending())
    surface.setPosition({60, 50, 420, 280})
    Swag.require(not surface.readback.isPending())
    Swag.require(surface.presentationWidth == surface.rc.width and surface.presentationHeight == surface.rc.height)
    Swag.require(surface.position == {60, 50, 420, 280})

    let expected = app.renderer.readRenderTarget(&surface.rt, 0, 0, surface.rc.width, surface.rc.height)
    let pixels   = Swag.makeSlice(cast(const [*] u8, unwrap surface.presentationPixels), expected.byteCount)
    Swag.require(Slice.equals(pixels, expected.pixels.toSlice()))

    button.disable()
    surface.paint()
    Swag.require(surface.readback.isPending())
    Swag.require(surface.presentationDirtyRect.width < cast(f32, surface.rc.width))
    Swag.require(surface.presentationDirtyRect.height < cast(f32, surface.rc.height))
    watch.restart()
    while surface.readback.isPending() and watch.elapsedMilliseconds() < 2000
    {
        discard surface.advanceNativePresentation()
        Threading.Thread.sleep(1'ms)
    }

    Swag.require(not surface.readback.isPending() and not surface.asynchronousPresentationFailed)
    let partial = app.renderer.readRenderTarget(&surface.rt, 0, 0, surface.rc.width, surface.rc.height)
    Swag.require(Slice.equals(pixels, partial.pixels.toSlice()))
    Swag.require(not surface.isDirty)
    var bounds: RECT
    let positioned = GetWindowRect(surface.win32Handle(), &bounds)
    Swag.require(positioned)
    Swag.require(bounds.left == 60 and bounds.top == 50 and bounds.right == 480 and bounds.bottom == 330)

    button.enable()
    surface.paint()
    Swag.require(surface.readback.isPending())
    surface.showNormalAt(#copy surface.position)
    Swag.require(not surface.readback.isPending())
    let placed = app.renderer.readRenderTarget(&surface.rt, 0, 0, surface.rc.width, surface.rc.height)
    Swag.require(Slice.equals(pixels, placed.pixels.toSlice()))

    let verified = expect Testing.verifyNativePresentation(surface)
    Swag.require(verified)

    // A green loading state must not conceal corrupted pixels in the published bitmap.
    let bitmap = cast([*] u8, surface.presentationPixels)
    let saved  = bitmap[0]
    bitmap[0] ^= 1
    var corruption: Swag.Error
    discard catch Testing.verifyNativePresentation(surface) as corruption
    bitmap[0] = saved
    Swag.require(corruption.value() != null)

    // A failed GPU submission preserves the published bitmap and schedules a complete repaint.
    // The native error arrives after recording, so allocation checks cannot consume it first.
    var inject = true
    surface.wnd.view.hookOnEvent = func|&inject|(_, evt)->bool
    {
        if inject and evt is PaintEvent
        {
            glScissor(0, 0, 1, -1)
            inject = false
        }

        return false
    }

    var retained: Array'u8
    retained.add(pixels)
    surface.invalidate()
    surface.paint()
    Swag.require(not surface.renderFailure.isEmpty() and surface.isDirty)
    Swag.require(not surface.readback.isPending())
    Swag.require(Slice.equals(retained.toSlice(), pixels))
    surface.paint()
    Swag.require(surface.renderFailure.isEmpty())
    watch.restart()
    while surface.readback.isPending() and watch.elapsedMilliseconds() < 2000
    {
        discard surface.advanceNativePresentation()
        Threading.Thread.sleep(1'ms)
    }

    Swag.require(expect Testing.verifyNativePresentation(surface))

    // Invalid expected pixels must fail verification, not compare two empty slices as equal.
    glBindFramebuffer(GL_FRAMEBUFFER, cast(GLuint, surface.rt.handle))
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 0, 0)
    var unavailable: Swag.Error
    discard catch Testing.verifyNativePresentation(surface) as unavailable
    glBindFramebuffer(GL_FRAMEBUFFER, cast(GLuint, surface.rt.handle))
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, cast(GLuint, surface.rt.colorBuffer.handle), 0)
    glBindFramebuffer(GL_FRAMEBUFFER, 0)
    Swag.require(unavailable.value() != null)
}
