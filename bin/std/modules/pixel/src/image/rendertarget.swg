#global public

// Identifies an off-screen color target and its optional depth/stencil surface.
//
// Handles are owned by the renderer that created the target. A `RenderTarget`
// value is a lightweight descriptor; renderer operations control allocation and
// release of the underlying graphics resources.
struct RenderTarget
{
    readonly
    {
        handle:       RenderTargetHandle            // Renderer-owned target handle.
        colorBuffer:  Texture                       // Texture receiving color output.
        depthStencil: RenderTargetSurfaceHandle     // Renderer-owned depth/stencil surface, or the invalid handle.
    }

    internal
    {
        paintAlpha:    bool     // Whether alpha requires a separate resolve pass.
        paintAlphaIdx: u64      // Renderer sequence number associated with the alpha resolve state.
    }
}

impl RenderTarget
{
    // Establishes a descriptor for resources created by a renderer.
    internal mtd attach(handle: RenderTargetHandle, textureHandle: TextureHandle, pixelFormat: PixelFormat, width, height: s32, depthStencil = InvalidRenderTargetSurfaceHandle)
    {
        .handle       = handle
        .depthStencil = depthStencil
        .colorBuffer.attach(textureHandle, pixelFormat, width, height)
    }

    // Invalidates a descriptor after its renderer has released the resources.
    internal mtd clear()
    {
        @init(me, 1)
    }
}
