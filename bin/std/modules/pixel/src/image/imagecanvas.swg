#global public

using Core, Core.Errors, Core.Math

// Draws into an image with the full painter, without a window.
//
// A canvas owns an off-screen rendering context and the render target behind it, so a program
// that only writes files reaches every painter capability — paths, brushes, gradients,
// textures, text, clipping, blending, transforms — and reads the result back as pixels. It is
// the same pipeline a window paints through, pointed at an image instead of a screen.
//
// Record into [[Pixel.ImageCanvas.painter]], then call [[Pixel.ImageCanvas.toImage]]. A canvas
// can be reused: drawing again after a read starts a new frame over a cleared target.
//
// ## Example
//
// ```swag
// var canvas = try ImageCanvas.create(256, 256)
// canvas.clear(Color.fromRgb(11, 11, 13))
//
// var path: LinePath
// path.start(32, 32)
// path.lineTo(224, 32)
// path.lineTo(128, 224)
// path.close()
// canvas.painter.fillPath(&path, Color.fromRgb(247, 249, 0))
//
// var image = try canvas.toImage()
// try image.save("triangle.png")
// ```
struct ImageCanvas
{
    painter: Painter     // Records the drawing; every painter operation is available.

    // The size of the surface being drawn, established by 'create'.
    readonly
    {
        width:  s32     // Canvas width, in pixels.
        height: s32     // Canvas height, in pixels.
    }

    // The graphics resources behind the canvas. They are opened by 'create' and released when
    // the canvas leaves scope.
    //
    // The renderer and the target live on the heap because the renderer keeps a pointer to the
    // bound target: moving either of them, as returning a canvas by value would, leaves that
    // pointer behind. On the heap their addresses outlive every move of the canvas itself.
    internal
    {
        renderer:   #null *RenderOgl        // Owns the target and issues the draw calls.
        target:     #null *RenderTarget     // Color target the painter draws into.
        context:    RenderingContext        // Off-screen rendering context.
        source:     Texture                 // Existing pixels drawn under every frame, if any.
        hasSource:  bool                    // Whether the canvas was opened over an image.
        background: Color                   // Color the target is cleared with.
        isOpen:     bool                    // Whether the graphics resources are live.
    }
}

impl ImageCanvas
{
    // Opens an off-screen canvas with positive dimensions.
    //
    // Fails when the platform cannot provide a rendering context. The canvas starts cleared to
    // fully transparent.
    func create(width, height: s32)->ImageCanvas fail
    {
        var result: retval
        try open(&result, width, height)
        return result
    }

    // Opens the graphics resources of a canvas in place.
    //
    // A canvas owns heap resources that its drop releases, so it is filled where it will live
    // rather than built somewhere else and handed over: one copy would leave two owners of the
    // same renderer.
    private func open(canvas: *ImageCanvas, width, height: s32) fail
    {
        Debug.assert(width > 0 and height > 0, "invalid dimensions")

        canvas.width      = width
        canvas.height     = height
        canvas.background = Color.fromArgb(0'u8, 0'u8, 0'u8, 0'u8)

        canvas.renderer = Memory.new'RenderOgl()
        canvas.target   = Memory.new'RenderTarget()

        let renderer = notnull canvas.renderer
        canvas.context = catch renderer.native.createOffscreenContext(width, height) as err
        if err != null
        {
            Memory.delete(canvas.renderer)
            Memory.delete(canvas.target)
            canvas.renderer = null
            canvas.target   = null
            fail err
        }

        canvas.isOpen = true
        renderer.begin(canvas.context)
        renderer.init()
        dref notnull canvas.target = renderer.createRenderTarget(width, height)
        renderer.end()

        canvas.painter.begin()
        canvas.painter.setColorMaskFull()
    }

    // Opens a canvas over an existing image, to draw on top of it.
    //
    // The image is uploaded once and laid down under every frame, so the recorded drawing
    // composites over it exactly as it would over a window's previous content. The source
    // image itself is never modified; each read returns a new one.
    //
    // ## Example
    //
    // ```swag
    // var photo  = try Image.load("photo.png")
    // var canvas = try ImageCanvas.create(photo)
    // canvas.painter.drawString(&font, 8, 8, "caption", Color.fromRgb(255, 255, 255))
    // var stamped = try canvas.toImage()
    // ```
    func create(image: Image)->ImageCanvas fail
    {
        if !image.isValid() do
            fail InvalidFormatError{"invalid image"}

        var result: retval
        try open(&result, image.width, image.height)

        let renderer = notnull result.renderer
        renderer.begin(result.context)
        result.source = renderer.addImage(image)
        renderer.end()
        result.hasSource = true
        return result
    }

    // Sets the color the target is cleared with before the recorded drawing is rendered.
    mtd clear(color: Color)
    {
        .background = color
    }

    // Renders everything recorded so far and returns the pixels.
    //
    // The painter is left ready to record the next frame, so a canvas can produce a series of
    // images without being opened again.
    mtd toImage()->Image fail
    {
        if !.isOpen do
            fail InvalidFormatError{"the canvas is closed"}

        .painter.end()

        let viewport   = Math.Rectangle{0, 0, cast(f32) .width, cast(f32) .height}
        let hasGround  = .background.a != 0
        let needsUnder = hasGround or .hasSource

        // The ground and the source image belong under the frame, so they are recorded in their
        // own pass rather than in the caller's painter, which would put them above whatever was
        // drawn first.
        var under: Painter
        if needsUnder
        {
            under.begin()
            under.setColorMaskFull()
            under.setBlendingMode(.Copy)
            if hasGround do
                under.fillRect(viewport, .background)
            if .hasSource do
                under.drawTexture(viewport, .source)
            under.end()
        }

        var target   = viewport
        let renderer = notnull .renderer
        renderer.begin(.context)
        renderer.bindRenderTarget(notnull .target, vp: &target)
        renderer.setScissorRect(viewport)
        renderer.clear()
        if needsUnder do
            renderer.draw(&under)
        renderer.draw(&.painter)

        var result: retval = renderer.unbindRenderTargetToImage(0, 0, .width, .height)
        renderer.end()

        .painter.begin()
        .painter.setColorMaskFull()
        return result
    }

    // Releases the graphics resources when the canvas leaves scope.
    mtd opDrop()
    {
        if !.isOpen do
            return
        .isOpen = false

        let renderer = notnull .renderer
        renderer.begin(.context)
        renderer.deleteRenderTarget(notnull .target)
        renderer.end()
        renderer.native.dropContext(.context)

        Memory.delete(.renderer)
        Memory.delete(.target)
        .renderer = null
        .target   = null
    }
}
