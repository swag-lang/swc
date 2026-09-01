#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// A document holding one of everything the painter treats differently: filled and stroked
// shapes, a gradient, a dash pattern, round and miter joins, a clip path, a rotated text
// block, and a group transform. Its elements are spread over a tall view box so a viewport
// only ever holds a few of them.
private const ViewportSource = #raw """
<svg viewBox="0 0 200 900">
  <defs>
    <linearGradient id="g" x1="0" x2="1">
      <stop offset="0" stop-color="#204080"/>
      <stop offset="1" stop-color="#c04020"/>
    </linearGradient>
    <clipPath id="c"><rect x="10" y="120" width="120" height="80"/></clipPath>
  </defs>
  <rect x="0" y="0" width="200" height="900" fill="#f0ece4"/>
  <circle cx="60" cy="60" r="40" fill="url(#g)" stroke="#101010" stroke-width="4"/>
  <rect x="10" y="120" width="180" height="120" fill="#3080c0" clip-path="url(#c)"/>
  <path d="M10 280 L60 320 L110 270 L160 330" fill="none" stroke="#802040" stroke-width="9" stroke-linejoin="round" stroke-linecap="round"/>
  <path d="M10 380 L60 420 L110 370 L160 430" fill="none" stroke="#206040" stroke-width="9" stroke-linejoin="miter"/>
  <path d="M10 470 C60 430 140 530 190 480" fill="none" stroke="#404040" stroke-width="3" stroke-dasharray="12 6"/>
  <g transform="translate(20,560) rotate(12)">
    <text x="0" y="0" font-size="22" fill="#202020" font-family="Georgia, serif">Viewport</text>
    <text x="0" y="34" font-size="14" fill="#606060">second run</text>
  </g>
  <g transform="translate(0,660) scale(0.8)">
    <ellipse cx="120" cy="80" rx="90" ry="50" fill="#e0b040" stroke="#403010" stroke-width="6"/>
  </g>
  <text x="100" y="860" text-anchor="middle" font-size="20" fill="#104020">bottom line</text>
</svg>
"""

// Renders `width` by `height` pixels of a drawing, optionally under a clipping rectangle.
private func renderViewport(drawing: const *Svg.Drawing, width, height: s32, x, y, scale: f32, clip: Math.Rectangle, useClip: bool)->Image
{
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    cpu.begin(width, height)

    var target  = renderer.createRenderTarget(width, height)
    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target, paintAlpha: false)
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    if useClip do
        painter.pushClippingSurfaceRect(clip)
    drawing.paint(&painter, x, y, scale)
    if useClip do
        painter.popClippingRect()
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)

    var result: retval = renderer.readRenderTarget(&target, 0, 0, width, height)
    renderer.deleteRenderTarget(&target)
    renderer.end()
    return result
}

// Counts the pixels of `rect` the two images disagree on.
//
// Only the colors are compared. The overlap-safe stroke pass uses the destination alpha as
// its own scratch plane and clears it across whatever the scissor allows, so the alpha a
// target is left holding depends on the clipping rectangle by construction; the document
// paints its own opaque ground, so a missing element shows in the colors.
private func differingPixels(a, b: const *Image, rect: Math.Rectangle)->u64
{
    var result = 0'u64
    for y in cast(s32) rect.y until cast(s32) rect.bottom()
    {
        for x in cast(s32) rect.x until cast(s32) rect.right() where (a.pixelColor(x, y).argb & 0xFFFFFF) != (b.pixelColor(x, y).argb & 0xFFFFFF) do
            result += 1
    }

    return result
}

// A painter told what it can reach paints exactly what an unbounded one paints there.
//
// Painting rejects an element whose bounds fall outside the clipping rectangle, so an
// element wrongly measured would go missing from the clipped render and only from it. Both
// renders below therefore have to agree pixel for pixel inside the rectangle, at a scale
// where most of the document is outside it and at one where none of it is.
#test
{
    var drawing = expect Svg.Drawing.parse(ViewportSource)

    const Width  = 200's32
    const Height = 260's32

    for scale in [0.28'f32, 1.0]
    {
        for offset in [0.0'f32, -180, -420, -700]
        {
            let clip    = Math.Rectangle{20, 30, 150, 190}
            let clipped = renderViewport(&drawing, Width, Height, 0, offset, scale, clip, true)
            let whole   = renderViewport(&drawing, Width, Height, 0, offset, scale, clip, false)
            Swag.assert(differingPixels(&clipped, &whole, clip) == 0)
        }
    }
}

// Shown smaller than its own units, a document still draws the picture it draws at full
// detail.
//
// A minified pass walks a contour in steps of one tolerance and drops the joins whose wedge
// cannot reach a pixel, so what it leaves out is by construction below the grid it is drawn
// on. [[Pixel.Svg.Drawing.rasterize]] declares no scale and therefore keeps every point and
// every join; the two renders are the same picture, and only their sub-pixel edges may
// disagree.
#test
{
    // A dense document: contours whose points are far closer together than the pixels it is
    // about to be drawn on, which is the case the minified pass exists for.
    var source: String
    source += "<svg viewBox='0 0 1600 1600'><rect width='1600' height='1600' fill='#f4f1ea'/>"
    for band in 12
    {
        source.appendFormat("<path fill='none' stroke='#%{X02}3050' stroke-width='%' d='M20 %", 40 + band * 16, 2 + band, 60 + band * 128)
        for step in 700 do
            source.appendFormat("L% %", 20 + cast(f32) step * 2.24, 60 + band * 128 + Math.sin(cast(f32) step * 0.09) * 44)
        source += "'/>"
    }

    for ring in 40 do
        source.appendFormat("<circle cx='%' cy='%' r='%' fill='none' stroke='#205030' stroke-width='3'/>", 60 + (ring % 10) * 160, 1560 - (ring / 10) * 26, 6 + ring % 7)
    source += "</svg>"

    var drawing = expect Svg.Drawing.parse(source.toString())

    const Scale  = 0.0625'f32
    const Width  = 100's32     // 1600 * Scale
    const Height = 100's32

    let clip     = Math.Rectangle{0, 0, cast(f32) Width, cast(f32) Height}
    let minified = renderViewport(&drawing, Width, Height, 0, 0, Scale, clip, true)
    let detailed = drawing.rasterize(Width, Height, 1)

    // Rasterizing reads its target back bottom-up, and so does the viewport render, so the
    // two carry their rows the same way round.
    var total = 0'u64
    for y in Height
    {
        for x in Width
        {
            let a = minified.pixelColor(x, y)
            let b = detailed.pixelColor(x, y)
            total += cast(u64) Math.abs(cast(s32) a.r - cast(s32) b.r)
            total += cast(u64) Math.abs(cast(s32) a.g - cast(s32) b.g)
            total += cast(u64) Math.abs(cast(s32) a.b - cast(s32) b.b)
        }
    }

    // Averaged over every channel of every pixel, in thousandths of a level. Sub-pixel edge
    // disagreement lands well under one level; a band or a ring the minified pass had lost
    // would be worth tens of them.
    let average = total * 1000 / (cast(u64) Width * cast(u64) Height * 3)
    Swag.assert(average < 2000)
}

// Rejecting elements does not depend on the order the viewports were painted in, and a
// drawing painted once whole still paints the same afterwards.
#test
{
    var drawing = expect Svg.Drawing.parse(ViewportSource)

    const Width  = 200's32
    const Height = 260's32

    let clip  = Math.Rectangle{0, 0, cast(f32) Width, cast(f32) Height}
    let first = renderViewport(&drawing, Width, Height, 0, -300, 1, clip, true)
    discard renderViewport(&drawing, Width, Height, 0, 0, 0.28, clip, true)
    discard renderViewport(&drawing, Width, Height, 0, -700, 1, clip, true)
    let again = renderViewport(&drawing, Width, Height, 0, -300, 1, clip, true)
    Swag.assert(differingPixels(&first, &again, clip) == 0)
}
