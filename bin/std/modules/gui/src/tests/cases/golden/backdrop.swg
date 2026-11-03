#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// Compare light frosted-glass materials over the two-to-four-pixel reading range.
func backdropMaterialSheet(light: bool)->Image
{
    var sheet = Image.create(1140, 780, .BGRA8)
    for tint, row in [0.08'f32, 0.14, 0.20]
    {
        for radius, column in [2.0'f32, 3.5, 4.0]
        {
            var host: Testing.HeadlessHost
            let lens = backdropLens(&host, light, 0.5)
            lens.open()
            lens.backdrop = BackdropEffect{algorithm: .Gaussian, radius: radius * 3, saturation: 1,
                                           tint: host.theme.colors.floating_Shadow.withAlphaF32(tint)}
            lens.input.setPlaceholder(Format.toString("% px / tint %", radius, cast(s32, Math.round(tint * 100))))
            let image = host.render()
            sheet.mix(image, cast(s32, column) * 380, (2 - cast(s32, row)) * 260)
        }
    }

    return sheet
}

#[Swag.TestTag("golden")]
#test
{
    let image = backdropMaterialSheet(false)
    Pixel.Testing.assertImageGolden(&image, "backdrop.materials.ink")
}

#[Swag.TestTag("golden")]
#test
{
    let image = backdropMaterialSheet(true)
    Pixel.Testing.assertImageGolden(&image, "backdrop.materials.paper")
}

#[Swag.TestTag("golden")]
#test
{
    let light = false
    var host: Testing.HeadlessHost
    let lens  = backdropLens(&host, light)
    lens.open()
    let image = host.renderSettled()
    Pixel.Testing.assertImageGolden(&image, light ? "backdrop.lens.paper" : "backdrop.lens.ink")
}
