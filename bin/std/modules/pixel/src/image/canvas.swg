#global public

using Core, Core.Errors, Core.Math

// Draws into an image with the full painter, without a window.
//
// A canvas owns a CPU renderer and the render target behind it, so a program
// that only writes files can render paths, brushes, gradients, textures, text, clipping,
// blending, and transforms and read the result back as pixels.
// The same backend powers display-independent image generation and pixel tests.
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
    public painter: Painter     // Records the drawing; every painter operation is available.

    // The size of the surface being drawn, established by 'create'.

    public readonly
    {
        width:  s32     // Canvas width, in pixels.
        height: s32     // Canvas height, in pixels.
    }

    // The rendering resources behind the canvas. They are opened by 'create' and released when
    // the canvas leaves scope.
    //
    // The renderer and the target live on the heap because the renderer keeps a pointer to the
    // bound target: moving either of them, as returning a canvas by value would, leaves that
    // pointer behind. On the heap their addresses outlive every move of the canvas itself.

    internal
    {
        renderer:   #null *RenderCpu        // Owns the target and executes painter commands.
        target:     #null *RenderTarget     // Color target the painter draws into.
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
    // The canvas starts cleared to fully transparent.
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

        canvas.renderer = Memory.new'RenderCpu()
        canvas.target   = Memory.new'RenderTarget()

        let renderer = canvas.renderer!
        canvas.isOpen = true
        renderer.begin(width, height)
        let rendererItf: IRenderer = renderer
        rendererItf.init()
        canvas.target![] = rendererItf.createRenderTarget(width, height)
        rendererItf.end()

        canvas.painter = Painter.create(renderer)
        canvas.painter.begin()
        canvas.beginFrame()
    }

    // Opens a frame on the target.
    //
    // The target is bound through the painter, with `paintAlpha`, because that is what tells
    // the renderer to resolve alpha separately. Antialiased strokes reach the pixels through a
    // pass that uses the destination alpha as scratch and leaves it at zero; without that
    // resolve every antialiased stroke would read back fully transparent. The ground is laid
    // with alpha writes enabled, and the content that follows draws color only, exactly as an
    // off-screen layer does.
    private mtd beginFrame()
    {
        .painter.bindRenderTarget(.target!, true)
        .painter.setColorMaskFull()
        .painter.clear(.background)
        .painter.setColorMaskColor()

        if .hasSource
        {
            .painter.setBlendingMode(.Copy)
            .painter.drawTexture({0, 0, cast(f32) .width, cast(f32) .height}, .source)
            .painter.setBlendingMode(.Alpha)
        }
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

        let renderer = result.renderer!
        renderer.begin(result.width, result.height)
        let rendererItf: IRenderer = renderer
        result.source = rendererItf.addImage(image)
        rendererItf.end()
        result.hasSource = true

        result.painter.setBlendingMode(.Copy)
        result.painter.drawTexture({0, 0, cast(f32) result.width, cast(f32) result.height}, result.source)
        result.painter.setBlendingMode(.Alpha)
        return result
    }

    // Lays a solid ground under the drawing recorded so far.
    //
    // The ground is written with alpha enabled, so a canvas can produce either an opaque image
    // or one that keeps its transparency, and it is remembered for the frames that follow.
    mtd clear(color: Color)
    {
        .background = color
        .painter.setColorMaskFull()
        .painter.clear(color)
        .painter.setColorMaskColor()
    }

    // Renders everything recorded so far and returns the pixels.
    //
    // The painter is left ready to record the next frame, so a canvas can produce a series of
    // images without being opened again.
    mtd toImage()->Image fail
    {
        if !.isOpen do
            fail InvalidFormatError{"the canvas is closed"}

        // An antialiased pass uses the destination alpha as scratch and leaves only its own
        // coverage there, which eats the ground laid at the start of the frame. An opaque
        // ground is therefore stamped back over the whole surface, in alpha only, exactly as a
        // window does before it presents. A transparent ground keeps the coverage instead:
        // that is what makes a mark with a see-through background come out right.
        if .background.a == 255
        {
            .painter.setBlendingMode(.Copy)
            .painter.setColorMaskAlpha()
            .painter.fillRect({0, 0, cast(f32) .width, cast(f32) .height}, .background)
            .painter.setColorMaskColor()
            .painter.setBlendingMode(.Alpha)
        }

        .painter.unbindRenderTarget()
        .painter.end()

        let renderer = .renderer!
        renderer.begin(.width, .height)
        let rendererItf: IRenderer = renderer
        .painter.render()
        var result: retval = rendererItf.readRenderTarget(.target!, 0, 0, .width, .height)
        rendererItf.end()

        .painter.begin()
        .beginFrame()
        return result
    }

    // Releases the graphics resources when the canvas leaves scope.
    mtd opDrop()
    {
        if !.isOpen do
            return
        .isOpen = false

        let renderer = .renderer!
        renderer.begin(.width, .height)
        let rendererItf: IRenderer = renderer
        rendererItf.deleteRenderTarget(.target!)
        rendererItf.end()

        Memory.delete(.renderer)
        Memory.delete(.target)
        .renderer = null
        .target   = null
    }
}
