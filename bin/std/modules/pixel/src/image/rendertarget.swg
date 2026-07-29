#global public

// Identifies an off-screen color target and its optional depth/stencil surface.
//
// Handles are owned by the renderer that created the target. A `RenderTarget`
// value is a lightweight descriptor; renderer operations control allocation and
// release of the underlying graphics resources.
struct RenderTarget
{
    handle:       RenderTargetHandle         // Renderer-owned target handle.
    colorBuffer:  Texture                    // Texture receiving color output.
    depthStencil: RenderTargetSurfaceHandle  // Renderer-owned depth/stencil surface, or the invalid handle.

    paintAlpha:    bool // Whether alpha requires a separate resolve pass.
    paintAlphaIdx: u64  // Renderer sequence number associated with the alpha resolve state.
}
