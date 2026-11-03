#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core, Pixel

struct SettledPaintWnd
{
    using wnd: Wnd
    paints:    u32
    animate:   bool
    value:     f32
}

impl IWnd for SettledPaintWnd
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        if evt.kind != .Content do
            return
        .paints += 1
        if .animate and .paints == 1
        {
            discard .app().animator.animateF32(me,
                                               AnimationChannel.from("test.settled.paint"),
                                               0,
                                               1,
                                               func(wnd, value)
                                               {
                                                   let target = assume cast(*SettledPaintWnd, wnd)
                                                   target.value = value
                                               },
                                               {duration: 100'ms})
        }

        evt.paintContext.painter.fillRect(.clientRect(), .value == 1 ? Argb.White : Argb.Black)
    }
}

// Capturing an idle tree paints it once; a paint-started track reaches its endpoint before capture.

// An application can select the CPU backend before its first surface; creation then follows the
// normal GUI lifecycle without allocating a native window or replacing that backend with OpenGL.

// The headless host must exercise the complete GUI paint path, not only record commands.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(96, 64)

    let background = host.render()
    Swag.assert(background.isValid())
    Swag.assert(background.width == 96 and background.height == 64)
    Swag.assert(background.pixelFormat == .BGRA8)

    let button  = PushButton.create(&host.root, "", {20, 16, 56, 32})
    let enabled = host.render()
    Swag.assert(not Slice.equals(enabled.pixels.toSlice(), background.pixels.toSlice()))
    Pixel.Testing.assertImageGolden(&enabled, "widget.cpu.pushbutton")

    button.disable()
    let disabled = host.render()
    Swag.assert(not Slice.equals(disabled.pixels.toSlice(), enabled.pixels.toSlice()))
}

// A repaint is normally one control wide, and the tree it sits in is a whole window. A window
// that cannot reach the region being repainted records nothing at all, instead of recording
// commands for the painter to clip away afterwards.

// Rejecting a window on a tighter rectangle than the one it dirties would leave the difference
// stale, so the region `invalidate` marks for a window is always enough to repaint it.
