#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

func pixelAt(image: const *Image, x, y: s32)->u32
{
    let idx = (cast(u64) y * cast(u64) image.width + cast(u64) x) * 4
    let ptr = (notnull image.pixels.buffer) + idx
    return dref cast(const *u32) ptr
}

// A device scale of 2 renders the same logical tree into a doubled physical target:
// logical geometry lands on scaled device pixels while the window tree stays logical.
#test
{
    var host: Testing.HeadlessHost
    host.setup(96, 64, dpiScale: 2)
    defer host.shutdown()

    @assert(host.surface.dpiScale == 2)
    @assert(host.surface.size().x == 96 and host.surface.size().y == 64)

    let background = host.render()
    @assert(background.width == 192 and background.height == 128)

    // A view-background child at logical (16, 8, 32, 24) must cover the physical
    // rectangle (32, 16, 64, 48).
    let child = Wnd.create'Wnd(&host.root, {16, 8, 32, 24})
    child.backgroundStyle = .View
    let framed = host.render()

    let inside  = pixelAt(&framed, 48, 28)
    let outside = pixelAt(&framed, 24, 28)
    @assert(inside != outside)

    // The edges sit on the device grid: just outside the left edge still shows the
    // parent background, just inside shows the child.
    @assert(pixelAt(&framed, 30, 28) == outside)
    @assert(pixelAt(&framed, 34, 28) == inside)
    @assert(pixelAt(&framed, 62, 28) == inside)
    @assert(pixelAt(&framed, 66, 28) == outside)
}

// The identical logical tree rendered at scale 1 and scale 2 must agree: the scaled
// image is the same picture with doubled geometry, not a different layout.
#test
{
    var host1: Testing.HeadlessHost
    host1.setup(96, 64)
    let child1 = Wnd.create'Wnd(&host1.root, {16, 8, 32, 24})
    child1.backgroundStyle = .View
    let image1 = host1.render()
    host1.shutdown()

    var host2: Testing.HeadlessHost
    host2.setup(96, 64, dpiScale: 2)
    defer host2.shutdown()
    let child2 = Wnd.create'Wnd(&host2.root, {16, 8, 32, 24})
    child2.backgroundStyle = .View
    let image2 = host2.render()

    // Compare well inside each region, away from antialiased edges.
    @assert(pixelAt(&image1, 24, 20) == pixelAt(&image2, 48, 40))
    @assert(pixelAt(&image1, 8, 8) == pixelAt(&image2, 16, 16))
    @assert(pixelAt(&image1, 90, 60) == pixelAt(&image2, 180, 120))
}
