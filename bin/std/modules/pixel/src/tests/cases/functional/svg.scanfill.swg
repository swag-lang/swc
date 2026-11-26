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
