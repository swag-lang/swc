#global public

using Core, Core.Math

// Routes painter command streams to one concrete rendering backend.
//
// The renderer is a borrowed view: the selected [[Pixel.RenderOgl]] or
// [[Pixel.RenderCpu]] must outlive it. Applications can switch backend without
// changing painters, layers, texture ownership calls, or render-target code.
// Select a backend before any other call. Textures and render targets remain
// owned by the backend that created them and must not cross a backend switch.
struct PainterRenderer
{
    private
    {
        ogl: #null *RenderOgl
        cpu: #null *RenderCpu
    }
}

impl PainterRenderer
{
    // Selects an OpenGL renderer and borrows it until another backend is selected.
    //
    // Resources created before a switch remain owned by their original backend.
    mtd setBackend(renderer: *RenderOgl)
    {
        Debug.assert(renderer != null)
        .ogl = renderer
        .cpu = null
    }

    // Selects a CPU renderer and borrows it until another backend is selected.
    //
    // Resources created before a switch remain owned by their original backend.
    mtd setBackend(renderer: *RenderCpu)
    {
        Debug.assert(renderer != null)
        .ogl = null
        .cpu = renderer
    }

    // Reports whether the selected backend renders in software.
    mtd const isSoftware()->bool => .cpu != null

    // Reports whether a concrete backend has been selected.
    mtd const hasBackend()->bool => .ogl != null or .cpu != null

    // Returns the glyph cache owned by the selected backend.
    //
    // The pointer remains valid until the backend is switched or destroyed.
    mtd fontCache()->*FontCache
    {
        if .cpu do
            return &.cpu.fonts
        return &(notnull .ogl).fonts
    }

    // Initializes backend resources.
    //
    // Call this once after selecting the backend. OpenGL requires a current
    // context; the CPU backend needs no initialization.
    mtd init()
    {
        if .cpu do
            return
        (notnull .ogl).init()
    }

    // Selects the native context used by subsequent OpenGL work.
    //
    // For the CPU backend, the context contributes only its pixel dimensions.
    mtd setCurrentContext(rc: RenderingContext)
    {
        if .cpu do
            .cpu.begin(rc.width, rc.height)
        else do
            (notnull .ogl).setCurrentContext(rc)
    }

    // Starts a frame in the selected backend.
    mtd begin(rc: RenderingContext)
    {
        if .cpu do
            .cpu.begin(rc.width, rc.height)
        else do
            (notnull .ogl).begin(rc)
    }

    // Finishes the current frame.
    mtd end()
    {
        if .cpu do
            .cpu.end()
        else do
            (notnull .ogl).end()
    }

    // Clears the active target to transparent black.
    mtd clear()
    {
        if .cpu do
            .cpu.clear()
        else do
            (notnull .ogl).clear()
    }

    // Returns the active target size in pixels.
    mtd targetSize()->{ width, height: s32 }
    {
        if .cpu do
            return .cpu.targetSize()
        return (notnull .ogl).targetSize()
    }

    // Restricts following writes to a surface-space rectangle.
    mtd setScissorRect(rect: Math.Rectangle)
    {
        if .cpu do
            .cpu.setScissorRect(rect)
        else do
            (notnull .ogl).setScissorRect(rect)
    }

    // Disables the surface-space scissor rectangle.
    mtd resetScissorRect()
    {
        if .cpu do
            .cpu.resetScissorRect()
        else do
            (notnull .ogl).resetScissorRect()
    }

    // Executes a completed painter command stream synchronously.
    mtd draw(painter: *Painter)
    {
        if .cpu do
            .cpu.draw(painter)
        else do
            (notnull .ogl).draw(painter)
    }

    // Binds an off-screen target for following direct operations.
    //
    // `vp` is used by OpenGL. CPU rendering always addresses the target's
    // complete pixel buffer.
    mtd bindRenderTarget(target: *RenderTarget, vp: #null *Math.Rectangle = null)
    {
        if .cpu do
            .cpu.bindRenderTarget(target)
        else do
            (notnull .ogl).bindRenderTarget(target, vp)
    }

    // Reads a rectangle of an off-screen target into a new image.
    mtd readRenderTarget(target: const *RenderTarget, x, y, width, height: s32)->Image
    {
        if .cpu do
            return .cpu.readRenderTarget(target, x, y, width, height)
        return (notnull .ogl).readRenderTarget(target, x, y, width, height)
    }

    // Reads the active target, then restores its parent target.
    mtd unbindRenderTargetToImage(x, y, width, height: s32)->Image
    {
        if .cpu do
            return .cpu.unbindRenderTargetToImage(x, y, width, height)
        return (notnull .ogl).unbindRenderTargetToImage(x, y, width, height)
    }

    // Restores the previous render target or the frame surface.
    mtd unbindRenderTarget()
    {
        if .cpu do
            .cpu.unbindRenderTarget()
        else do
            (notnull .ogl).unbindRenderTarget()
    }

    // Creates an off-screen target owned by the selected backend.
    mtd createRenderTarget(width, height: s32)->RenderTarget
    {
        if .cpu do
            return .cpu.createRenderTarget(width, height)
        return (notnull .ogl).createRenderTarget(width, height)
    }

    // Releases an off-screen target and invalidates its descriptor.
    mtd deleteRenderTarget(target: *RenderTarget)
    {
        if .cpu do
            .cpu.deleteRenderTarget(target)
        else do
            (notnull .ogl).deleteRenderTarget(target)
    }

    // Loads an image file into a texture owned by the selected backend.
    mtd addImage(fullName: string)->Texture fail
    {
        if .cpu do
            return try .cpu.addImage(fullName)
        return try (notnull .ogl).addImage(fullName)
    }

    // Copies an image into a texture owned by the selected backend.
    mtd addImage(image: Image)->Texture
    {
        if .cpu do
            return .cpu.addImage(image)
        return (notnull .ogl).addImage(image)
    }

    // Replaces all bytes of a texture owned by the selected backend.
    mtd updateTexture(texture: Texture, pixels: const *u8)
    {
        if .cpu do
            .cpu.updateTexture(texture, pixels)
        else do
            (notnull .ogl).updateTexture(texture, pixels)
    }

    // Reads a texture into the requested tightly packed pixel format.
    mtd readTexturePixels(texture: Texture, pixelFormat: PixelFormat)->Array'u8
    {
        if .cpu do
            return .cpu.readTexturePixels(texture, pixelFormat)
        return (notnull .ogl).readTexturePixels(texture, pixelFormat)
    }

    // Releases a texture and invalidates its descriptor.
    mtd removeTexture(texture: *Texture)
    {
        if .cpu do
            .cpu.removeTexture(texture)
        else do
            (notnull .ogl).removeTexture(texture)
    }

    // Translates following painter submissions in surface pixels.
    mtd translateTransform(x, y: f32)
    {
        if .cpu do
            .cpu.translateTransform(x, y)
        else do
            (notnull .ogl).translateTransform(x, y)
    }

    // Rotates following painter submissions around the surface origin.
    mtd rotateTransform(angle: Math.Angle)
    {
        if .cpu do
            .cpu.rotateTransform(angle)
        else do
            (notnull .ogl).rotateTransform(angle)
    }

    // Rotates following painter submissions around a surface-space center.
    mtd rotateTransform(angle: Math.Angle, centerX, centerY: f32)
    {
        if .cpu do
            .cpu.rotateTransform(angle, centerX, centerY)
        else do
            (notnull .ogl).rotateTransform(angle, centerX, centerY)
    }

    // Scales following painter submissions independently on both axes.
    mtd scaleTransform(x, y: f32)
    {
        if .cpu do
            .cpu.scaleTransform(x, y)
        else do
            (notnull .ogl).scaleTransform(x, y)
    }

    // Scales following painter submissions uniformly.
    mtd scaleTransform(scale: f32)
    {
        if .cpu do
            .cpu.scaleTransform(scale)
        else do
            (notnull .ogl).scaleTransform(scale)
    }

    // Restores the identity world transform.
    mtd resetTransform()
    {
        if .cpu do
            .cpu.resetTransform()
        else do
            (notnull .ogl).resetTransform()
    }

    // Acquires a pooled off-screen target at least as large as requested.
    mtd acquireRenderTarget(width, height: s32)->*RenderTarget
    {
        if .cpu do
            return .cpu.acquireRenderTarget(width, height)
        return (notnull .ogl).acquireRenderTarget(width, height)
    }

    // Returns a pooled target to the selected backend; `null` is ignored.
    mtd releaseRenderTarget(target: #null *RenderTarget)
    {
        if .cpu do
            .cpu.releaseRenderTarget(target)
        else do
            (notnull .ogl).releaseRenderTarget(target)
    }
}
