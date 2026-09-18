#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Number of pixels that differ from the background, which the corner of the image gives.
func inkCount(image: const *Image)->s32
{
    let background = image.pixelColor(0, 0).argb

    var result = 0
    for y in cast(s32) image.height
    {
        for x in cast(s32) image.width
        {
            if image.pixelColor(x, y).argb != background do
                result += 1
        }
    }

    return result
}

// Renders a spinner stopped at one phase, on its own host drawn at `dpiScale`.
func renderSpinner(dpiScale: f32)->Image
{
    var host: Testing.HeadlessHost
    host.setup(64, 64, dpiScale)
    defer host.shutdown()

    let spin = Spinner.create(&host.root, {16, 16, 32, 32})
    spin.animationPhase = 0.25
    return host.render()
}

// A spinner takes its square from the theme when the caller gives no measurement.
#test
{
    var host: Testing.HeadlessHost
    host.setup(64, 64)
    defer host.shutdown()

    let size = host.root.themeMetrics().spinner_Size
    let spin = Spinner.create(&host.root, {8, 8})
    Swag.assert(spin.position.width == size and spin.position.height == size)
}

// Painting advances the cycle and wraps it, so a spinner left on screen never stops and never
// runs its phase out of range.
#test
{
    var host: Testing.HeadlessHost
    host.setup(64, 64)
    defer host.shutdown()

    let spin = Spinner.create(&host.root, {16, 16, 32, 32})
    spin.animationPhase = 0.95
    discard host.render()
    Swag.assert(spin.animationPhase >= 0 and spin.animationPhase < 1)
}

// The ring is drawn, never sampled from an atlas: rendering the same logical spinner at twice the
// density covers four times the pixels, which is what a resolution-independent form means. A
// sprite sheet would resample one frame and land far from that ratio.
#test
{
    let image1 = renderSpinner(1)
    let image2 = renderSpinner(2)
    let ink1   = inkCount(&image1)
    let ink2   = inkCount(&image2)

    Swag.assert(ink1 > 0)
    Swag.assert(image2.width == 2 * image1.width and image2.height == 2 * image1.height)

    // Four times the area, give or take the antialiased rim of eight small disks.
    let ratio = cast(f32) ink2 / cast(f32) ink1
    Swag.assert(ratio > 3.5 and ratio < 4.5)
}
