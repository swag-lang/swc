#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

struct ScrollThumbSamples
{
    using wnd: Wnd
}

impl IWnd for ScrollThumbSamples
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let theme = .theme()
        let color = .themeColors().scrollBar_PressedBox
        let painter = evt.paintContext.painter
        theme.drawSubRect(painter, {8, 8, 4, 16}, &theme.rects.scrollBar_BoxV, color)
        theme.drawSubRect(painter, {24, 8, 4, 40}, &theme.rects.scrollBar_BoxV, color)
        theme.drawSubRect(painter, {48, 8, 16, 4}, &theme.rects.scrollBar_BoxH, color)
        theme.drawSubRect(painter, {48, 24, 40, 4}, &theme.rects.scrollBar_BoxH, color)
    }
}

// A minimal thumb keeps the same end caps as a longer thumb, in both directions and on every pixel grid.
#test
{
    for scale in [1.0'f32, 1.25, 1.5, 2.0]
    {
        var host: Testing.HeadlessHost
        host.setup(104, 64, dpiScale: scale)
        let samples = Wnd.create'ScrollThumbSamples(&host.root, "", {0, 0, 104, 64})
        samples.backgroundStyle = .View
        var image = host.render(samples)
        Swag.require(image.pixelColor(cast(s32, 10 * scale), cast(s32, 16 * scale)) != host.theme.colors.view_Bk)

        for x in cast(s32, 4 * scale) do
            for y in cast(s32, 2 * scale)
            {
                let shortTop = image.pixelColor(cast(s32, 8 * scale) + x, cast(s32, 8 * scale) + y)
                let longTop = image.pixelColor(cast(s32, 24 * scale) + x, cast(s32, 8 * scale) + y)
                let shortBottom = image.pixelColor(cast(s32, 8 * scale) + x, cast(s32, 24 * scale) - 1 - y)
                let longBottom = image.pixelColor(cast(s32, 24 * scale) + x, cast(s32, 48 * scale) - 1 - y)
                Swag.require(shortTop == longTop and shortBottom == longBottom)

                let shortLeft = image.pixelColor(cast(s32, 48 * scale) + y, cast(s32, 8 * scale) + x)
                let longLeft = image.pixelColor(cast(s32, 48 * scale) + y, cast(s32, 24 * scale) + x)
                let shortRight = image.pixelColor(cast(s32, 64 * scale) - 1 - y, cast(s32, 8 * scale) + x)
                let longRight = image.pixelColor(cast(s32, 88 * scale) - 1 - y, cast(s32, 24 * scale) + x)
                Swag.require(shortLeft == longLeft and shortRight == longRight)
            }
    }
}
