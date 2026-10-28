#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

const IconButtonHeadless_Command = "IconButtonHeadless.Command"

var IconButtonHeadlessPressedCount: u32
var IconButtonHeadlessCheckCount:   u32

func iconButtonHeadlessPressed(_: *Button)
{
    IconButtonHeadlessPressedCount += 1
}

func iconButtonHeadlessChecked(_: *IconButton)
{
    IconButtonHeadlessCheckCount += 1
}

func iconButtonHeadlessReset()
{
    IconButtonHeadlessPressedCount = 0
    IconButtonHeadlessCheckCount   = 0
}

// A plain icon button posts a command and fires sigPressed on click.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)
    host.recordCommands()
    iconButtonHeadlessReset()

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40})
    btn.sigPressed += &iconButtonHeadlessPressed

    host.click({40, 40})
    Swag.assert(IconButtonHeadlessPressedCount == 1)
    Swag.assert(not btn.isChecked)
}

// A Toggle button flips its checked state on every click.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)
    host.recordCommands()
    iconButtonHeadlessReset()

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40}, IconButtonHeadless_Command)
    btn.updateFlags(.Toggle)
    btn.sigCheckedChanged += &iconButtonHeadlessChecked

    host.click({40, 40})
    Swag.assert(btn.isChecked)
    Swag.assert(IconButtonHeadlessCheckCount == 1)

    host.click({40, 40})
    Swag.assert(not btn.isChecked)
    Swag.assert(IconButtonHeadlessCheckCount == 2)
}

// A radio button can only be set, never unset, by user activation.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)
    host.recordCommands()
    iconButtonHeadlessReset()

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40})
    btn.updateFlags(.Radio)
    btn.sigCheckedChanged += &iconButtonHeadlessChecked

    host.click({40, 40})
    Swag.assert(btn.isChecked)
    Swag.assert(IconButtonHeadlessCheckCount == 1)

    host.click({40, 40})
    Swag.assert(btn.isChecked)
    Swag.assert(IconButtonHeadlessCheckCount == 1)
}

// Programmatic checked-state changes support both stateful modes and remain silent.
#test
{
    var host: Testing.HeadlessHost
    host.setup(180, 120)
    iconButtonHeadlessReset()

    let toggle = IconButton.create(&host.root, {}, {20, 20, 40, 40}, flags: .Toggle)
    toggle.sigCheckedChanged += &iconButtonHeadlessChecked
    toggle.setChecked(true)
    Swag.assert(toggle.isChecked)
    Swag.assert(IconButtonHeadlessCheckCount == 0)

    toggle.setChecked(false)
    Swag.assert(not toggle.isChecked)
    Swag.assert(IconButtonHeadlessCheckCount == 0)

    let radio = IconButton.create(&host.root, {}, {80, 20, 40, 40}, flags: .Radio)
    radio.sigCheckedChanged += &iconButtonHeadlessChecked
    radio.setChecked(true)
    Swag.assert(radio.isChecked)
    Swag.assert(IconButtonHeadlessCheckCount == 0)
}

// Space and Enter activate a focused toggle with the same state, signal, and command contract as a click.
#test
{
    var host: Testing.HeadlessHost
    host.setup(180, 120)
    host.recordCommands()
    iconButtonHeadlessReset()

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40}, IconButtonHeadless_Command, .Toggle)
    btn.sigCheckedChanged += &iconButtonHeadlessChecked
    host.focus(btn)

    host.keyPress(Input.Key.Space)
    Swag.assert(btn.isChecked)
    host.keyPress(Input.Key.Return)
    Swag.assert(not btn.isChecked)
    Swag.assert(IconButtonHeadlessCheckCount == 2)
    Swag.assert(host.commandCount == 2 and host.lastCommand == IconButtonHeadless_Command)
}

// Number of pixels painted in one exact color.
func iconButtonColorCount(image: const *Image, color: Color)->s32
{
    var result = 0
    for y in cast(s32, image.height)
    {
        for x in cast(s32, image.width)
        {
            if image.pixelColor(x, y).argb == color.argb do
                result += 1
        }
    }

    return result
}

// A checked button draws the indicator its placement asks for, and none at all when it asks
// for none.
//
// An indicator on one edge is the two-pixel Arc rule of a tab underline. Drawn under a color
// swatch, a field of a form, or a preset cell painted in the user's own colors, it would read as
// one more thing painted in the cell, which is why the two indicator-less placements draw none.
#test
{
    var host: Testing.HeadlessHost
    host.setup(80, 80)

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40}, flags: .Toggle)
    btn.setForm(.Rectangle)
    btn.setChecked(true)

    let rule = host.theme.colors.btnIcon_CheckedRule
    Swag.assert(rule.a == 255)

    for indicator in [IconButtonCheckIndicator.None, .Ink]
    {
        btn.setCheckIndicator(indicator)
        host.finishAnimations()
        var image = host.render()
        Swag.assert(iconButtonColorCount(&image, rule) == 0)
    }

    for indicator in [IconButtonCheckIndicator.Bottom, .Top, .Left, .Right]
    {
        btn.setCheckIndicator(indicator)
        host.finishAnimations()
        var image = host.render()
        Swag.assert(iconButtonColorCount(&image, rule) > 0)
    }

    // A full mark and a frame are the selection ground and an Arc ring around the whole cell.
    btn.setCheckIndicator(.Ink)
    host.finishAnimations()
    let unmarked = host.render()
    for indicator in [IconButtonCheckIndicator.Full, .Frame]
    {
        btn.setCheckIndicator(indicator)
        host.finishAnimations()
        var marked = host.render()
        Swag.assert(not Slice.equals(marked.pixels.toSlice(), unmarked.pixels.toSlice()))
        Swag.assert(iconButtonColorCount(&marked, rule) == 0)
    }
}

// The checked frame is drawn on the shape the button has.
//
// A rectangular tool takes the control corner like a rounded one. The frame and the focus ring
// have to follow that corner, or either mark crosses the fill at the corners — which leaves the
// corner pixel of the cell on the ground it stands on.
#test
{
    var host: Testing.HeadlessHost
    host.setup(80, 80)

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40}, flags: .Toggle)
    btn.setCheckIndicator(.Frame)
    btn.setChecked(true)

    for light in [false, true]
    {
        if light do
            host.theme.setLight()
        else do
            host.theme.setDark()
        host.notify(.ThemeChanged)

        for form in [IconButtonForm.RoundedRectangle, .Rectangle]
        {
            btn.setForm(form)
            host.finishAnimations()
            var image = host.render()
            Swag.assert(btn.focusRingRadius == host.theme.rects.btnIcon_SquareBk.radius)
            Swag.assert(image.pixelColor(20, 20) == host.theme.colors.dlg_Bk)
        }
    }
}

// A checked tool is written in Arc in both themes, and never in the ink of a fill.
#test
{
    var host: Testing.HeadlessHost
    host.setup(80, 80)

    let btn = IconButton.create(&host.root, host.theme.icon(.Filter, 24), {20, 20, 40, 40}, flags: .Toggle)
    btn.setChecked(true)

    for light in [false, true]
    {
        if light do
            host.theme.setLight()
        else do
            host.theme.setDark()
        host.notify(.ThemeChanged)

        for indicator in [IconButtonCheckIndicator.Full, .Frame]
        {
            btn.setCheckIndicator(indicator)
            host.finishAnimations()
            var image = host.render()
            let glyph = host.theme.colors.btnIcon_CheckedIcon
            Swag.assert(glyph == host.theme.colors.arc)
            Swag.assert(iconButtonColorCount(&image, glyph) > 0)
        }
    }
}

// The two indicator-less placements differ by what they leave the state colors saying: `None`
// reads as pressed, `Ink` keeps the checked ink so the glyph itself carries the state.
#test
{
    var host: Testing.HeadlessHost
    host.setup(80, 80)

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40}, flags: .Toggle)
    btn.setForm(.Rectangle)
    btn.setChecked(true)

    let colors = host.theme.colors

    btn.setCheckIndicator(.None)
    host.finishAnimations()
    var pressed = host.render()
    Swag.assert(iconButtonColorCount(&pressed, colors.btnIcon_CheckedPressedBk) > 0)

    btn.setCheckIndicator(.Ink)
    host.finishAnimations()
    var ink = host.render()
    Swag.assert(iconButtonColorCount(&ink, colors.btnIcon_CheckedPressedBk) == 0)
}

// Hiding a button resets both its pointer state and its animated overlay state.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)
    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40})
    btn.isHot          = true
    btn.isPressed      = true
    btn.aniBk.themeCrc = 42'u32

    btn.hide()

    Swag.assert(not btn.isHot)
    Swag.assert(not btn.isPressed)
    Swag.assert(btn.aniBk.themeCrc == Swag.U32.Max)
}

// Disabling a button keeps it in the layout, but still drops transient input/paint state.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)
    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40})
    btn.isHot              = true
    btn.isIn               = true
    btn.isPressed          = true
    btn.isPressing         = true
    btn.aniBk.themeCrc     = 42'u32
    host.app.mouseEnterWnd = btn
    host.app.setMouseCaptureRaw(btn)

    btn.disable()

    Swag.assert(not btn.isHot)
    Swag.assert(not btn.isIn)
    Swag.assert(not btn.isPressed)
    Swag.assert(not btn.isPressing)
    Swag.assert(btn.aniBk.themeCrc == Swag.U32.Max)
    Swag.assert(host.app.mouseEnterWnd == null)
    Swag.assert(host.app.mouseCaptureWnd == null)
}

// An icon button answers what its content needs, so a longer wording widens the button
// instead of being crowded by it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)

    let icon = host.root.theme().icon(ThemeIcons.Play, 18)
    let btn  = IconButton.create(&host.root, icon, {0, 0, 80, 30}, IconButtonHeadless_Command)
    btn.setText("Save")
    btn.setTextPosition(.Right)

    let short = btn.itf.measureContent({320, 200})
    btn.setText("Enregistrer sous")
    let long = btn.itf.measureContent({320, 200})
    Swag.assert(long.x > short.x)
    Swag.assert(long.y == short.y)

    // Stacked, the same wording grows the other axis instead.
    btn.setTextPosition(.Bottom)
    let stacked = btn.itf.measureContent({320, 200})
    Swag.assert(stacked.y > short.y)

    // A button hiding its label answers for the icon alone, whatever the wording is.
    btn.updateFlags(.IconOnly)
    let hidden = btn.itf.measureContent({320, 200})
    btn.setText("A much longer caption nobody sees")
    Swag.assert(btn.itf.measureContent({320, 200}).x == hidden.x)
}

// A compact toolbar menu centers icon, wording, and disclosure as one horizontal group. Its
// outer air and both inner gaps share one rhythm instead of tightening toward either edge.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 68)

    let metrics = &host.theme.metrics
    Swag.assert(metrics.btnIcon_Padding == metrics.btnIcon_SpacingTextH)
    Swag.assert(metrics.btnIcon_SpacingArrowH == metrics.btnIcon_SpacingTextH)

    let btn = IconButton.create(&host.root, host.theme.icon(.Redo, 18), {20, 16, 120, 36}, flags: .CenterContent)
    btn.setArrowPosition(.RightDownward)
    let iconOnly = btn.itf.measureContent({160, 68})
    Swag.assert(iconOnly.x == 2 * metrics.btnIcon_Padding + 18 + metrics.btnIcon_SpacingArrowH + metrics.btnIcon_ArrowSize)
    Swag.assert(iconOnly.y == 2 * metrics.btnIcon_Padding + 18)

    btn.setText("View")
    btn.setTextPosition(.Right)
    let withText = btn.itf.measureContent({160, 68})
    Swag.assert(withText.x > iconOnly.x + metrics.btnIcon_SpacingTextH)
    Swag.assert(withText.y == iconOnly.y)

    host.settleAnimations(&host.root, 4)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "iconbutton.menu-arrow")
}
