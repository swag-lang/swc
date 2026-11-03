#global public

using Core, Core.Math

// Reports a renderer resource that the graphics backend could not allocate or update.
struct RenderResourceError
{
    public using base: Swag.BaseError     // Message describing the refused resource operation.
}

// Describes one drawable owned by an [[Pixel.IRenderer]].
//
// The renderer creates and invalidates this value. `data` is opaque backend
// state; callers preserve it unchanged and only read the dimensions and opaque
// render handle.
struct RenderContext
{
    public
    {
        renderHandle: const *void?     // Platform drawable handle, or `null` for an off-screen context.
        data:         *void?           // Opaque renderer-owned state.
        width:        s32              // Drawable width, in pixels.
        height:       s32              // Drawable height, in pixels.
    }
}

// Executes painter command streams and owns every resource created through it.
//
// `IRenderer` is a borrowed dynamic interface. [[Pixel.RenderOgl]],
// [[Pixel.RenderCpu]], and third-party backends implement the same contract, so
// code that records or submits painter work does not need a closed backend list.
// The concrete renderer must outlive the interface value, its painters, and all
// textures and render targets created through it.
interface IRenderer
{
    // Reports whether contexts created by this backend need a platform drawable.
    mtd const needsNativeWindow()->bool

    // Creates a context for an opaque platform drawable or an off-screen surface.
    //
    // `shared` is borrowed during the call and belongs to this same renderer.
    // The returned context remains owned by the caller until [[Pixel.IRenderer.deleteContext]].
    mtd createContext(renderHandle: const *void?, width, height: s32, shared: *RenderContext? = null)->RenderContext fail

    // Releases renderer state held by `context` and invalidates the descriptor.
    mtd deleteContext(context: *RenderContext)

    // Returns the glyph cache owned by this renderer.
    //
    // The pointer remains valid until the concrete renderer is destroyed.
    mtd fontCache()->*FontCache

    // Initializes renderer-owned resources.
    //
    // Call this once before creating textures or submitting painter work.
    // OpenGL requires a current context; software backends may do nothing.
    mtd init()

    // Selects the rendering context used by following operations.
    //
    // A backend that does not use a platform context may use only its dimensions.
    mtd setCurrentContext(rc: RenderContext)

    // Starts a frame for `rc` and resets the renderer transform.
    mtd begin(rc: RenderContext)

    // Finishes the current frame and presents it when the backend has a display surface.
    mtd end()

    // Clears the active target to transparent black.
    mtd clear()

    // Returns the active target size in pixels.
    mtd targetSize()->{ width, height: s32 }

    // Restricts following direct writes to a surface-space rectangle.
    mtd setScissorRect(rect: Math.Rectangle)

    // Disables the surface-space scissor rectangle.
    mtd resetScissorRect()

    // Executes a completed painter command stream synchronously.
    mtd draw(painter: *Painter)

    // Binds an off-screen target for following direct operations.
    //
    // `vp` optionally limits the viewport. A backend may use the complete target
    // when it has no distinct viewport state.
    mtd bindRenderTarget(target: *RenderTarget, vp: *Math.Rectangle? = null)

    // Reads a rectangle of an off-screen target into a new image.
    //
    // Returns an invalid image if the backend cannot complete the transfer.
    mtd readRenderTarget(target: const *RenderTarget, x, y, width, height: s32)->Image

    // Reads the active target, then restores its parent target.
    //
    // Returns an invalid image if the backend cannot complete the transfer.
    mtd unbindRenderTargetToImage(x, y, width, height: s32)->Image

    // Restores the previous render target or the frame surface.
    mtd unbindRenderTarget()

    // Creates an off-screen target owned by this renderer.
    //
    // Returns a target with an invalid color buffer when the backend cannot allocate it.
    mtd createRenderTarget(width, height: s32)->RenderTarget

    // Releases an off-screen target and invalidates its descriptor.
    mtd deleteRenderTarget(target: *RenderTarget)

    // Loads an image file into a texture owned by this renderer.
    mtd addImage(fullName: string)->Texture fail

    // Copies an image into a texture owned by this renderer.
    //
    // Returns an invalid texture if the source is invalid or the backend cannot upload it.
    mtd addImage(image: Image)->Texture

    // Copies a planar 4:2:0 or 4:4:4 picture into a texture owned by this renderer.
    //
    // The result carries [[Pixel.PixelFormat.Yuv420]] or [[Pixel.PixelFormat.Yuv444]] according to
    // the view's chroma subsampling and draws like any other texture. A backend
    // with shaders keeps the planes and converts while it samples, which is why a decoder is
    // allowed to hand its picture over unconverted; one without converts here, once per upload.
    // Returns an invalid texture if the backend cannot allocate or upload every plane.
    mtd addImage(view: const *YuvPlanarView)->Texture

    // Replaces all bytes of a texture owned by this renderer.
    //
    // Returns false when the backend cannot complete the upload. The caller must stop using
    // the texture because its contents may have changed before the failure was reported.
    mtd updateTexture(texture: Texture, pixels: const *u8)->bool

    // Replaces the planar picture held by a texture created from a view.
    //
    // Returns false when the backend cannot complete every plane upload.
    mtd updateTexture(texture: Texture, view: const *YuvPlanarView)->bool

    // Reads a texture into the requested tightly packed pixel format.
    //
    // Returns an empty byte array if the backend cannot complete the transfer.
    mtd readTexturePixels(texture: Texture, pixelFormat: PixelFormat)->Array'u8

    // Releases a texture and invalidates its descriptor.
    mtd removeTexture(texture: *Texture)

    // Translates following painter submissions in surface pixels.
    mtd translateTransform(x, y: f32)

    // Rotates following painter submissions around the surface origin.
    mtd rotateTransform(angle: Math.Angle)

    // Rotates following painter submissions around a surface-space center.
    mtd rotateTransform(angle: Math.Angle, centerX, centerY: f32)

    // Scales following painter submissions independently on both axes.
    mtd scaleTransform(x, y: f32)

    // Scales following painter submissions uniformly.
    mtd scaleTransform(scale: f32)

    // Restores the identity world transform.
    mtd resetTransform()

    // Acquires a pooled off-screen target at least as large as requested.
    //
    // The OpenGL backend stops the command stream if the target cannot be allocated.
    mtd acquireRenderTarget(width, height: s32)->*RenderTarget

    // Returns a pooled target to this renderer; `null` is ignored.
    mtd releaseRenderTarget(target: *RenderTarget?)
}
