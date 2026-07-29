#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Command-stream goldens for widget painting.
//
// The headless suites next to this file check structure, geometry and events; none of them ever
// looks at what a widget *draws*. Painting a window tree into a bare painter and snapshotting the
// commands closes that gap without a GPU: a background that disappears, a border that stops being
// emitted, a disabled state that no longer changes anything, or a theme lookup returning the wrong
// color all show up as a line of diff. See [[Pixel.Testing.assertGolden]].
//
// These goldens are recorded at 'Batches' level: they hold the command sequence, the size of each
// batch, its bounds and its colors, but no texture coordinates. Colors are what most widget states
// come down to -- a disabled button draws the very same geometry as an enabled one -- so leaving
// them out would make those goldens indistinguishable. Texture coordinates are left out because
// they depend on where a glyph sits in its atlas.

// Glyph caches are keyed by typeface and size and shared by the whole process, and a cache that
// overflows spills into a second atlas. At the theme's default size the 200-odd other tests in this
// module have already filled the first atlas by the time these run, so which atlas a glyph lands in
// -- and therefore how the glyph batches split, which is visible in the command stream whatever the
// dump level -- depends on the test order. Painting at a size nothing else uses gives these goldens
// a cache of their own, small enough to always fit a single atlas.
private const WidgetGoldenFontSize = 17'u32

private func setupWidgetHost(host: *Testing.HeadlessHost, width, height: f32)
{
    host.setup(width, height)
    host.theme.res.fontDefault = host.theme.createDefaultFontfamily(WidgetGoldenFontSize)
}

private func assertPaintGolden(host: *Testing.HeadlessHost, name: string, loc = #callerlocation)
{
    var painter: Painter
    var bc:      PaintContext

    bc.painter  = &painter
    bc.renderer = host.app.getRenderer()

    painter.begin()
    host.root.paint(&bc)
    painter.end()

    Pixel.Testing.assertGolden(&painter, name, .Batches, loc)
}

// The empty root window, which every other golden here starts with.
#test
{
    var host: Testing.HeadlessHost
    setupWidgetHost(&host, 200, 80)
    assertPaintGolden(&host, "widget.root.empty")
}

#test
{
    var host: Testing.HeadlessHost
    setupWidgetHost(&host, 200, 80)

    discard PushButton.create(&host.root, "Ok", {20, 20, 160, 40})
    assertPaintGolden(&host, "widget.pushbutton")
}

// A disabled widget must paint differently: the theme picks disabled colors and the paint context
// carries the state down. An identical golden would mean the state never reached the painter.
#test
{
    var host: Testing.HeadlessHost
    setupWidgetHost(&host, 200, 80)

    let btn = PushButton.create(&host.root, "Ok", {20, 20, 160, 40})
    btn.disable()
    assertPaintGolden(&host, "widget.pushbutton.disabled")
}

// A hidden widget must paint nothing at all.
#test
{
    var host: Testing.HeadlessHost
    setupWidgetHost(&host, 200, 80)

    let btn = PushButton.create(&host.root, "Ok", {20, 20, 160, 40})
    btn.hide()
    assertPaintGolden(&host, "widget.pushbutton.hidden")
}

#test
{
    var host: Testing.HeadlessHost
    setupWidgetHost(&host, 200, 80)

    discard Label.create(&host.root, "Hello", {20, 20, 160, 24})
    assertPaintGolden(&host, "widget.label")
}

// Checked and unchecked must not produce the same commands: the check mark is a separate glyph or
// icon batch.
#test
{
    var host: Testing.HeadlessHost
    setupWidgetHost(&host, 200, 80)

    discard CheckButton.create(&host.root, "On", {20, 20, 160, 24})
    assertPaintGolden(&host, "widget.checkbutton.unchecked")
}

#test
{
    var host: Testing.HeadlessHost
    setupWidgetHost(&host, 200, 80)

    let chk = CheckButton.create(&host.root, "On", {20, 20, 160, 24})
    chk.toggle()
    assertPaintGolden(&host, "widget.checkbutton.checked")
}

#test
{
    var host: Testing.HeadlessHost
    setupWidgetHost(&host, 200, 80)

    discard RadioButton.create(&host.root, "One", {20, 20, 160, 24})
    assertPaintGolden(&host, "widget.radiobutton")
}

// The filled part of a progress bar is a second rectangle over the track, so an empty and a
// half-filled bar differ by one batch.
#test
{
    var host: Testing.HeadlessHost
    setupWidgetHost(&host, 240, 60)

    discard ProgressBar.create(&host.root, {20, 20, 200, 20})
    assertPaintGolden(&host, "widget.progressbar.empty")
}

#test
{
    var host: Testing.HeadlessHost
    setupWidgetHost(&host, 240, 60)

    let bar = ProgressBar.create(&host.root, {20, 20, 200, 20})
    bar.setProgression(0.5)
    assertPaintGolden(&host, "widget.progressbar.half")
}

#test
{
    var host: Testing.HeadlessHost
    setupWidgetHost(&host, 240, 60)

    discard Slider.create(&host.root, {20, 20, 200, 20})
    assertPaintGolden(&host, "widget.slider")
}

#test
{
    var host: Testing.HeadlessHost
    setupWidgetHost(&host, 240, 60)

    discard EditBox.create(&host.root, "text", {20, 20, 200, 24})
    assertPaintGolden(&host, "widget.editbox")
}

// Siblings paint in z-order, so the golden records the order the tree is walked in.
#test
{
    var host: Testing.HeadlessHost
    setupWidgetHost(&host, 240, 120)

    discard PushButton.create(&host.root, "A", {10, 10, 100, 30})
    discard PushButton.create(&host.root, "B", {10, 50, 100, 30})
    discard Label.create(&host.root, "C", {130, 10, 100, 30})
    assertPaintGolden(&host, "widget.siblings.zorder")
}

// A clipping parent must push a clipping rectangle before painting its children, and a child fully
// outside it must emit nothing.
#test
{
    var host: Testing.HeadlessHost
    setupWidgetHost(&host, 240, 120)

    let view = Wnd.create'Wnd(&host.root, {10, 10, 100, 50})
    view.wndFlags.add(.ClipChildren)
    discard PushButton.create(view, "In", {5, 5, 60, 20})
    discard PushButton.create(view, "Out", {5, 200, 60, 20})
    assertPaintGolden(&host, "widget.clipchildren")
}
