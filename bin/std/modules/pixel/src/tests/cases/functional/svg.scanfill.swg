#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Scan the original winding across both tile axes, including a fractional edge.
#test
{
    const Source = """
        <svg width='37' height='29'>
          <path fill='#244769' fill-rule='%' d='M1.25 1H35.5V27H1.25Z M7 5H22V17H7Z'/>
        </svg>
        """
    for rule in ["evenodd", "nonzero"]
    {
        let source  = Format.toString(Source, rule)
        let drawing = expect Svg.Drawing.parse(source.toString(), {preferScanFills: true})
        var cpu:      RenderCpu
        let renderer: IRenderer = &cpu
        renderer.init()
        defer renderer.end()

        let tiled = drawing.rasterizeWithSampleTileSide(renderer, 37, 29, 1, 8, &cpu)
        let whole = drawing.rasterize(37, 29, 1)
        Swag.require(tiled.isValid() and whole.isValid())
        Swag.require(tiled.pixelColor(0, 0).argb == 0x00FF_FFFF)
        Swag.require(tiled.pixelColor(1, 3).argb == 0xBF24_4769)
        Swag.require(tiled.pixelColor(30, 13).argb == 0xFF24_4769)
        Swag.require(tiled.pixelColor(10, 10).a == (rule == "evenodd" ? 0 : 255))
        for value, index in tiled.pixels do
            Swag.require(value == whole.pixels[index])
    }
}

// Same-color layers retain their straight RGB while their opacity composes in order.
#test
{
    const Source = """
        <svg width='40' height='25' fill='#b8286d'>
          <path d='M1 1H25V19H1Z' fill-opacity='.5'/>
          <path d='M15 5H38V23H15Z' fill-opacity='.5'/>
          <path d='M0 0H40V25H0Z' opacity='0'/>
        </svg>
        """
    let drawing = expect Svg.Drawing.parse(Source, {preferScanFills: true})
    let image   = drawing.rasterize(40, 25, 1)
    Swag.require(image.isValid())
    Swag.require(image.pixelColor(4, 4).argb == 0x7FB8_286D)
    Swag.require(image.pixelColor(18, 9).argb == 0xBFB8_286D)
    Swag.require(image.pixelColor(35, 18).argb == 0x7FB8_286D)
    Swag.require(image.pixelColor(0, 24).argb == 0x00FF_FFFF)
}

// Curved holes wholly outside a tile give the same coverage as an untiled fill.
#test
{
    const Source = """
        <svg width='48' height='32'>
          <path fill-rule='evenodd' d='M1 1H47V31H1Z M2 2C12 2 12 6 2 6Z
                                     M35 22C45 22 45 28 35 28Z
                                     M14 16C18 16 26 2 28 16C24 30 18 16 14 16Z'/>
        </svg>
        """
    let drawing = expect Svg.Drawing.parse(Source, {preferScanFills: true})
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.init()
    defer renderer.end()

    let tiled = drawing.rasterizeWithSampleTileSide(renderer, 48, 32, 1, 8, &cpu)
    let whole = drawing.rasterize(48, 32, 1)
    Swag.require(tiled.isValid() and whole.isValid())
    Swag.require(tiled.pixelColor(4, 3).a == 0)
    Swag.require(tiled.pixelColor(38, 25).a == 0)
    Swag.require(tiled.pixelColor(16, 26).a == 255)
    for value, index in tiled.pixels do
        Swag.require(value == whole.pixels[index])
}

// A referenced clip and a different ink keep the general painter in charge.
#test
{
    const Source = """
        <svg width='40' height='24'>
          <defs><clipPath id='c'><rect width='13' height='20'/></clipPath></defs>
          <g clip-path='url(#c)'><path d='M1.25 1H37V23H1.25Z' fill='#162442'/></g>
          <path d='M22 4H35V18H22Z' fill='#b8286d'/>
        </svg>
        """
    let drawing = expect Svg.Drawing.parse(Source, {preferScanFills: true})
    let image   = drawing.rasterize(40, 24, 1)
    Swag.require(image.isValid())
    Swag.require(image.pixelColor(6, 6).argb == 0xFF16_2442)
    Swag.require(image.pixelColor(18, 5).a == 0)
    Swag.require(image.pixelColor(28, 9).argb == 0xFFB8_286D)

    let reference = expect Svg.Drawing.parse(Source)
    let previous  = reference.rasterize(40, 24, 1)
    for y in 24 do
        for x in 13 do
            Swag.require(image.pixelColor(x, y) == previous.pixelColor(x, y))
}

// Resolve supersamples after the intersecting fills have composed on that grid.
#test
{
    const Source = """
        <svg width='25' height='21'>
          <path d='M1.5 1.5H22V19H1.5Z' fill-opacity='.5'/>
          <path d='M1.5 1.5H13V16H1.5Z' fill-opacity='.5'/>
        </svg>
        """
    let drawing = expect Svg.Drawing.parse(Source, {preferScanFills: true})
    let image   = drawing.rasterize(25, 21, 2)
    Swag.require(image.isValid())
    Swag.require(image.pixelColor(1, 1).argb == 0x3000_0000)
    Swag.require(image.pixelColor(1, 6).argb == 0x6000_0000)
    Swag.require(image.pixelColor(7, 6).argb == 0xBF00_0000)
    Swag.require(image.pixelColor(20, 6).argb == 0x7F00_0000)
    Swag.require(image.pixelColor(24, 20).argb == 0x00FF_FFFF)
}

// Vertical sampling includes each edge's top endpoint and excludes its bottom.
#test
{
    const Source = """
        <svg width='11' height='7'>
          <path d='M1 .125H4V.375H1Z M5 .15625H8V.34375H5Z M1 1.625H4V1.375H1Z'/>
        </svg>
        """
    let drawing = expect Svg.Drawing.parse(Source, {preferScanFills: true})
    let image   = drawing.rasterize(11, 7, 1)
    Swag.require(image.isValid())
    Swag.require(image.pixelColor(2, 0).a == 64)
    Swag.require(image.pixelColor(6, 0).argb == 0x00FF_FFFF)
    Swag.require(image.pixelColor(2, 1).a == 64)
}

// Short signed coordinates can sit beside numbers that need the full parser.
#test
{
    const ShortNumbers = """
        <svg width='32' height='20'>
          <path d='M+2 1e0l+12-0 0+9-1.2e1 .0Z M1.6e1,2H2e1v+8h-4z M24 3L+28 3 +26 1e1'/>
        </svg>
        """
    const Equivalent   = """
        <svg width='32' height='20'>
          <path d='M2 1H14V10H2Z M16 2H20V10H16Z M24 3L28 3 26 10Z'/>
        </svg>
        """
    let options   = Svg.ParseOptions{preferScanFills: true}
    let drawing   = expect Svg.Drawing.parse(ShortNumbers, options)
    let reference = expect Svg.Drawing.parse(Equivalent, options)
    let image     = drawing.rasterize(32, 20, 1)
    let expected  = reference.rasterize(32, 20, 1)
    Swag.require(image.isValid() and expected.isValid())
    Swag.require(image.pixelColor(3, 5).a == 255)
    Swag.require(Memory.compare(image.pixels.storage(), expected.pixels.storage(), image.pixels.count) == 0)
}

// Scan single-row and multi-row edges while reusing scratch across different fill heights.
#test
{
    var source = String.from("<svg width='42' height='4'><path d='")
    for stripe in 20 do
        source.appendFormat("M% 0h.75l.5 .25h-.75z ", 1 + 2 * ((stripe * 7) % 20))
    source += "'/><path d='M3 1h.75l2.5 1.25h-.75z'/><path d='M10 3h.75l.5 .25h-.75z'/></svg>"

    let drawing = expect Svg.Drawing.parse(source.toString(), {preferScanFills: true})
    let image   = drawing.rasterize(42, 4, 1)
    Swag.require(image.isValid())
    const MiddleAlpha = [64'u8, 96, 32]
    for column in 42
    {
        let x = cast(s32, column)
        Swag.require(image.pixelColor(x, 0).a == (x % 2 == 1 and x < 40 ? 48 : 0))
        let middle = x >= 3 and x < 6 ? MiddleAlpha[x - 3] : 0
        Swag.require(image.pixelColor(x, 1).a == middle)
        Swag.require(image.pixelColor(x, 2).a == (x == 5 ? 48 : 0))
        Swag.require(image.pixelColor(x, 3).a == (x == 10 ? 48 : 0))
    }
}

// Reordering a medium crossing list must preserve coincident boundaries and either fill rule.
#test
{
    const Source = "<svg width='51' height='13'><path fill-rule='%' fill-opacity='.5' d='%'/></svg>"
    var segments: String
    for column in 24
    {
        let left  = 1.25 + cast(f32, (column * 7) % 24) * 2
        let right = left + 2
        segments.appendFormat("M% 2H%V11H%z ", left, right, left)
    }

    for rule in ["evenodd", "nonzero"]
    {
        let source    = Format.toString(Source, rule, segments.toString())
        let rectangle = Format.toString(Source, rule, "M1.25 2H49.25V11H1.25z")
        let options   = Svg.ParseOptions{preferScanFills: true}
        let drawing   = expect Svg.Drawing.parse(source.toString(), options)
        let reference = expect Svg.Drawing.parse(rectangle.toString(), options)
        let image     = drawing.rasterize(51, 13, 1)
        let expected  = reference.rasterize(51, 13, 1)
        Swag.require(image.isValid() and expected.isValid())
        Swag.require(image.pixelColor(23, 5).a == 127)
        Swag.require(Memory.compare(image.pixels.storage(), expected.pixels.storage(), image.pixels.count) == 0)
    }
}

// The row jobs for the first fill must finish before the translucent fill.
#[Swag.TestTag("parallel")]
#test
{
    var source: String
    source.append("<svg width='73' height='61'><path fill-rule='evenodd' d='M1 1H72V60H1Z ")
    for row in 8 do
        for column in 17 do
            source.append(Format.toString("M% %h2v2h-2z ", 4 + column * 4, 4 + row * 6).toString())
    source.append("'/><path fill-opacity='.5' d='M0 0H38V61H0Z'/></svg>")

    let drawing = expect Svg.Drawing.parse(source.toString(), {preferScanFills: true})
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.init()
    defer renderer.end()

    const Width  = 292
    const Height = 244
    let tiled = drawing.rasterizeWithSampleTileSide(renderer, Width, Height, 1, 128, &cpu)
    Swag.require(tiled.isValid())
    for 3
    {
        let whole = drawing.rasterize(Width, Height, 1)
        Swag.require(whole.isValid())
        Swag.require(whole.pixelColor(12, 12).a == 255)
        Swag.require(whole.pixelColor(16, 16).a == 127)
        Swag.require(whole.pixelColor(272, 184).a == 0)
        for value, index in tiled.pixels do
            Swag.require(value == whole.pixels[index])
    }
}

// A compound fill can prepare its contours independently, even when it needs finer
// curve points after a thumbnail. Separate rows of the same geometry scan serially.
#[Swag.TestTag("parallel")]
#test
{
    const Open = "<svg width='216' height='200'>"
    const Path = "<path fill-rule='evenodd' d='"
    var compound = String.from(Open)
    var rows     = String.from(Open)
    compound += Path
    for row in 32
    {
        var contours: String
        for column in 33
        {
            let x = 4 + column * 6
            let y = 4 + row * 6
            contours.appendFormat("M% %c7 -1 7 6 0 5z ", x, y)
        }

        compound += contours.toString()
        rows     += Path
        rows     += contours.toString()
        rows     += "'/>"
    }

    compound += "'/></svg>"
    rows     += "</svg>"
    let options   = Svg.ParseOptions{preferScanFills: true}
    let drawing   = expect Svg.Drawing.parse(compound.toString(), options)
    let reference = expect Svg.Drawing.parse(rows.toString(), options)
    for extent in [[108, 100], [432, 100], [432, 400], [432, 400]]
    {
        let width    = extent[0]
        let height   = extent[1]
        let actual   = drawing.rasterize(width, height, 1)
        let expected = reference.rasterize(width, height, 1)
        Swag.require(actual.isValid() and expected.isValid())
        let probe = width / 36
        Swag.require(actual.pixelColor(probe, probe).a > 0)
        Swag.require(Memory.compare(actual.pixels.storage(), expected.pixels.storage(), actual.pixels.count) == 0)
    }
}
