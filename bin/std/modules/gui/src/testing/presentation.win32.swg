#global public
#global namespace Testing
#global if #os == Swag.TargetOs.Windows

using Core, Pixel

// Compares the bitmap published to Windows with its completed OpenGL render target.
//
// Call on the window thread between event-loop frames. Returns false until a frame has
// been published. Fails if the surface has no OpenGL renderer or rendering
// or pixel inspection fails.
//
// This reads the GPU synchronously and is intended for smoke checkpoints. For composition
// effects such as translucency over other windows, inspect the desktop separately.
func verifyNativePresentation(surface: *Surface)->bool fail
{
    if not (surface.app.renderer is RenderOgl) do
        fail Errors.InvalidFormatError{Errors.mkString("presentation verification needs an OpenGL surface")}
    if not surface.renderFailure.isEmpty() do
        fail Errors.InvalidFormatError{Errors.mkString(surface.renderFailure.toString())}
    if not surface.presentedFrame do
        return false

    surface.app.renderer.setCurrentContext(surface.renderingContext())
    let tinted   = surface.hasDisabledTint() or surface.opacity < 1
    let target   = tinted ? &surface.presentationTarget : &surface.rt
    let width    = surface.rc.width
    let height   = surface.rc.height
    let expected = surface.app.renderer.readRenderTarget(target, 0, 0, width, height)
    if not expected.isValid() do
        fail Errors.InvalidFormatError{Errors.mkString("cannot read the GPU target for presentation verification")}

    let pixels    = cast(const [*] u8, unwrap surface.presentationPixels)
    let stride    = cast(u64, surface.presentationWidth) * 4
    let rowBytes  = cast(u64, width) * 4
    let firstRow  = cast(u64, surface.presentationHeight - height)
    let reference = expected.pixels.toSlice()
    for row in cast(u64, height)
    {
        let actual = Swag.makeSlice(pixels + (firstRow + row) * stride, rowBytes)
        let offset = row * rowBytes
        if not Slice.equals(actual, reference[offset until offset + rowBytes]) do
            return false
    }

    return true
}
