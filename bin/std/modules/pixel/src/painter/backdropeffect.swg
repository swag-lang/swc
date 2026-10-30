#global public

using Core, Core.Math

// Selects the spatial filter of a backdrop material.
enum BackdropBlur
{
    Gaussian       // Normalized separable Gaussian, suited to small radii.
    DualKawase     // Complementary downsample/reconstruction kernels; Gaussian below two device pixels.
}

// Defocuses already composited, opaque content without changing its alpha coverage.
//
// The material combines spatial filtering, saturation, and an optional tint. It samples only
// the current target, before subsequent foreground drawing. It owns no resources between frames.
// Transparent layers must first have an opaque ground: their RGB is not an opaque backdrop.
struct BackdropEffect
{
    public
    {
        algorithm:  BackdropBlur = .DualKawase     // Spatial filtering algorithm.
        radius:     f32          = 16     // Logical blur extent, clamped to zero through 64.
        saturation: f32          = 1      // Zero is grayscale; one preserves color; clamped to zero through two.
        tint:       Color        = Color.fromArgb(Argb.Zero)     // Optional straight-alpha color mixed into the filtered RGB.
        opacity:    f32          = 1      // Mix with the original backdrop, clamped to zero through one.
    }
}

// Parameters shared by the software and GPU material passes.
internal struct BackdropPass
{
    width, height: s32     // Valid source texels, excluding unused pooled-target storage.
    mode:          s32     // 0/1: Gaussian axes, 2: downsample, 3: reconstruct, 4: material.
    radius:        f32
    saturation:    f32 = 1
    tint:          Color
}

private struct BackdropImage
{
    target:        *RenderTarget
    width, height: s32
}

impl BackdropEffect
{
    // Filters the backdrop under `rect`, in translated painter coordinates.
    //
    // Scale and rotation of the painter transform are not supported. The caller must repaint
    // the sampled background each frame; repeatedly filtering an old frame accumulates blur.
    // Sampling extends beyond `rect` and clamps at the target edge. The current clipping region
    // limits the final composite only. Empty rectangles and zero opacity do no work. Drawing
    // state is restored, with the default built-in shader selected afterward. Numeric inputs
    // must be finite. Tinting and saturation operate on display RGB, without a gamma conversion.
    //
    // ```swag
    // let glass = BackdropEffect{radius: 16, saturation: 0.85}
    // glass.draw(&painter, panelRect)
    // // Draw the foreground after the material so it stays sharp.
    // ```
    mtd const draw(painter: *Painter, rect: Math.Rectangle)
    {
        Swag.assert(Math.isFinite(.opacity) and Math.isFinite(.radius) and Math.isFinite(.saturation))
        Swag.assert(Math.isFinite(rect.x) and
                    Math.isFinite(rect.y) and
                    Math.isFinite(rect.width) and
                    Math.isFinite(rect.height))
        let opacity = Math.saturate(.opacity)
        if opacity <= 0 or rect.isEmpty() or painter.isEmptyClippingRect() do
            return

        let transform = painter.transform()
        Swag.assert(transform.isTranslationOnly())
        let radius      = Math.clamp(.radius, 0.0, 64.0)
        let scale       = painter.contentScale()
        var destination = rect
        destination.offset(transform.tx, transform.ty)
        let bounds  = painter.backdropTargetBounds()
        var capture = destination

        // Include the reconstruction kernels' complete reach, not just the nominal extent.
        capture.inflate(radius * 8 + 4, radius * 8 + 4)
        capture.intersect(bounds)
        if capture.isEmpty() do
            return

        // Align the snapshot to device texels, including on fractional display scales.
        let left   = Math.floor(capture.x * scale)
        let top    = Math.floor(capture.y * scale)
        let right  = Math.min(Math.ceil(capture.right() * scale), Math.round(bounds.width * scale))
        let bottom = Math.min(Math.ceil(capture.bottom() * scale), Math.round(bounds.height * scale))
        let width  = cast(s32, right - left)
        let height = cast(s32, bottom - top)
        capture = {left / scale, top / scale, width / scale, height / scale}

        let renderer = painter.renderer()
        var content  = BackdropImage{renderer.acquireRenderTarget(width, height), width, height}
        painter.captureBackdrop(content.target, {left, top, width, height})
        painter.releaseRenderTarget(content.target)

        // All intermediate coordinates are logical; their textures retain device resolution.
        let pass = func|painter, renderer, scale|(source: BackdropImage,
                                                  w,
                                                  h: s32,
                                                  params: BackdropPass,
                                                  reuse: *RenderTarget?)->BackdropImage
        {
            let target = reuse orelse renderer.acquireRenderTarget(w, h)
            if not reuse do
                painter.releaseRenderTarget(target)
            painter.bindRenderTarget(target)
            painter.setAntialiased(false)
            painter.setInterpolationMode(.Linear)
            painter.setColorMaskFull()
            painter.setBlendingMode(.Copy)
            var filter = params
            filter.width  = source.width
            filter.height = source.height
            painter.setBackdropShader(filter)
            painter.drawTexture(Math.Rectangle{0, 0, w / scale, h / scale}, source.target.colorBuffer)
            painter.setDefaultShader()
            painter.unbindRenderTarget()
            return {target, w, h}
        }

        if radius > 0
        {
            let algorithm = radius * scale < 2 ? BackdropBlur.Gaussian : .algorithm
            switch #complete algorithm
            {
            case .Gaussian:

                // The capture is no longer read after the horizontal pass. Reuse its storage
                // for the vertical result; recorded commands preserve that dependency order.
                let captureTarget = content.target
                content = pass(content, width, height, {mode: 0, radius: radius * scale}, null)
                content = pass(content, width, height, {mode: 1, radius: radius * scale}, captureTarget)

            case .DualKawase:

                // Complementary kernels follow Marius Bjorge's dual filter (SIGGRAPH 2015).
                // Stop at a small pyramid and vary tap spacing for the remaining extent.
                var levels = 1
                var extent = 2.0'f32
                while extent < radius * scale and levels < 6
                {
                    levels += 1
                    extent *= 2
                }

                let offset = Math.max(0.5, radius * scale / extent)
                var sizes: [7] struct{x, y: s32}
                sizes[0] = {width, height}
                for level in levels
                {
                    let previous = sizes[level]
                    let w        = Math.max(1, (previous.x + 1) / 2)
                    let h        = Math.max(1, (previous.y + 1) / 2)
                    sizes[level + 1] = {w, h}
                    content = pass(content, w, h, {mode: 2, radius: offset}, null)
                }

                for var level = levels - 1; level >= 0; level -= 1 do
                    content = pass(content, sizes[level].x, sizes[level].y, {mode: 3, radius: offset}, null)
            }
        }

        painter.pushState()
        painter.resetTransform()
        painter.pushClippingSurfaceRect(destination)
        painter.setAntialiased(false)
        painter.setInterpolationMode(.Linear)
        painter.setColorMaskColor()
        painter.setBlendingMode(.Alpha)
        painter.setBackdropShader({width: width, height: height, mode: 4,
                                   saturation: Math.clamp(.saturation, 0.0, 2.0), tint: .tint})
        painter.drawTexture(capture, content.target.colorBuffer, Color.fromArgb(Argb.White).withAlphaF32(opacity))
        painter.setDefaultShader()
        painter.popClippingRect()
        painter.popState()
    }
}
