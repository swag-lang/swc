#global public
#global namespace Testing
#global if #os == Swag.TargetOs.Windows

using Core, Pixel

// Checks the native presentation bitmap against its completed OpenGL render target.
//
// Call on the window thread between event-loop frames. Polls a pending transfer without waiting
// and returns false until it or the first frame completes. Fails if the surface has no native
// OpenGL renderer, a transfer fell back after an error, or any presented byte differs. The
// comparison reads the GPU synchronously and is
// intended for smoke checkpoints, not performance measurements. Disabled surfaces use their
// tinted presentation target. This checks the bitmap handed to the compositor, not desktop capture.
func verifyNativePresentation(surface: *Surface)->bool fail
{
    if not (surface.app.renderer is RenderOgl) do
        fail Errors.InvalidFormatError{Errors.mkString("presentation verification needs an OpenGL surface")}
    if surface.readback.isPending() and not surface.advanceNativePresentation() do
        return false
    if surface.asynchronousPresentationFailed do
        fail Errors.InvalidFormatError{Errors.mkString("asynchronous presentation fell back after a transfer error")}
    if not surface.presentationPixels do
        return false

    surface.app.renderer.setCurrentContext(surface.renderingContext())
    let target   = surface.isDisabled and surface.app.fadeDisabledSurface ? &surface.presentationTarget : &surface.rt
    let expected = surface.app.renderer.readRenderTarget(target, 0, 0, surface.presentationWidth, surface.presentationHeight)
    let actual   = Swag.makeSlice(cast(const [*] u8, surface.presentationPixels), expected.byteCount)
    if not Slice.equals(actual, expected.pixels.toSlice()) do
        fail Errors.InvalidFormatError{Errors.mkString(Format.toString("presented pixels differ from the GPU target (% x %)",
                                                                       surface.presentationWidth,
                                                                       surface.presentationHeight))}
    return true
}
