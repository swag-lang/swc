#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Authored opacity must affect colors once, including when a stroke needs alpha scratch.
#test
{
    let drawing = expect Svg.Drawing.parse("<svg width='32' height='24'><rect width='32' height='24' fill='white'/><rect x='4' y='4' width='24' height='16' fill='#204060' fill-opacity='0.25'/><path d='M1 1H3' fill='none' stroke='black'/></svg>")
    for samples in [1'u8, 2'u8, 4'u8]
    {
        let image = drawing.rasterize(32, 24, samples)
        let color = image.pixelColor(16, 12)
        Swag.assert(Math.abs(cast(s32) color.r - 199) <= 2)
        Swag.assert(Math.abs(cast(s32) color.g - 207) <= 2)
        Swag.assert(Math.abs(cast(s32) color.b - 215) <= 2)
        Swag.assert(color.a == 255)
    }
}

// The exported image holds straight RGB and source-over coverage, not the maximum shape alpha.
#test
{
    let drawing = expect Svg.Drawing.parse("<svg width='24' height='16'><rect x='2' y='2' width='14' height='12' fill='red' fill-opacity='0.5'/><rect x='8' y='2' width='14' height='12' fill='blue' fill-opacity='0.5'/></svg>")
    let image = drawing.rasterize(24, 16, 2)
    let single = image.pixelColor(4, 8)
    Swag.assert(single.r >= 253 and single.g == 0 and single.b == 0)
    Swag.assert(Math.abs(cast(s32) single.a - 128) <= 2)
    let overlap = image.pixelColor(12, 8)
    Swag.assert(Math.abs(cast(s32) overlap.a - 192) <= 2)
    Swag.assert(Math.abs(cast(s32) overlap.r - 85) <= 3)
    Swag.assert(Math.abs(cast(s32) overlap.b - 170) <= 3)
    Swag.assert(image.pixelColor(0, 0).a == 0)
}

// Rotated content cannot contribute coverage outside its clip, or the hidden rectangle reappears.
#test
{
    let drawing = expect Svg.Drawing.parse("<svg width='32' height='32'><defs><clipPath id='c'><circle cx='16' cy='16' r='8'/></clipPath></defs><g clip-path='url(#c)'><rect x='3' y='3' width='26' height='26' transform='rotate(25 16 16)' fill='#806040' fill-opacity='0.3'/></g><path d='M15 15H17' stroke='red'/></svg>")
    let image = drawing.rasterize(32, 32, 2)
    Swag.assert(image.pixelColor(5, 5).a == 0)
    Swag.assert(image.pixelColor(5, 16).a == 0)
    Swag.assert(Math.abs(cast(s32) image.pixelColor(16, 20).a - 77) <= 2)
}
