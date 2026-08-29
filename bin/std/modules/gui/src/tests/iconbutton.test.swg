#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

const IconButtonHeadless_Command = "IconButtonHeadless.Command"

var IconButtonHeadlessPressedCount: u32
var IconButtonHeadlessCheckCount:   u32

func iconButtonHeadlessPressed(btn: *Button)
{
    discard btn
    IconButtonHeadlessPressedCount += 1
}

func iconButtonHeadlessChecked(btn: *IconButton)
{
    discard btn
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
    defer host.shutdown()
    host.recordCommands()
    iconButtonHeadlessReset()

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40})
    btn.sigPressed += &iconButtonHeadlessPressed

    host.click({40, 40})
    @assert(IconButtonHeadlessPressedCount == 1)
    @assert(!btn.isChecked)
}

// A Toggle button flips its checked state on every click.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)
    defer host.shutdown()
    host.recordCommands()
    iconButtonHeadlessReset()

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40}, IconButtonHeadless_Command)
    btn.updateFlags(.Toggle)
    btn.sigCheckedChanged += &iconButtonHeadlessChecked

    host.click({40, 40})
    @assert(btn.isChecked)
    @assert(IconButtonHeadlessCheckCount == 1)

    host.click({40, 40})
    @assert(!btn.isChecked)
    @assert(IconButtonHeadlessCheckCount == 2)
}

// A radio button can only be set, never unset, by user activation.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)
    defer host.shutdown()
    host.recordCommands()
    iconButtonHeadlessReset()

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40})
    btn.updateFlags(.Radio)
    btn.sigCheckedChanged += &iconButtonHeadlessChecked

    host.click({40, 40})
    @assert(btn.isChecked)
    @assert(IconButtonHeadlessCheckCount == 1)

    host.click({40, 40})
    @assert(btn.isChecked)
    @assert(IconButtonHeadlessCheckCount == 1)
}

// Programmatic checked-state changes support both stateful modes and remain silent.
#test
{
    var host: Testing.HeadlessHost
    host.setup(180, 120)
    defer host.shutdown()
    iconButtonHeadlessReset()

    let toggle = IconButton.create(&host.root, {}, {20, 20, 40, 40}, flags: .Toggle)
    toggle.sigCheckedChanged += &iconButtonHeadlessChecked
    toggle.setChecked(true)
    @assert(toggle.isChecked)
    @assert(IconButtonHeadlessCheckCount == 0)

    toggle.setChecked(false)
    @assert(!toggle.isChecked)
    @assert(IconButtonHeadlessCheckCount == 0)

    let radio = IconButton.create(&host.root, {}, {80, 20, 40, 40}, flags: .Radio)
    radio.sigCheckedChanged += &iconButtonHeadlessChecked
    radio.setChecked(true)
    @assert(radio.isChecked)
    @assert(IconButtonHeadlessCheckCount == 0)
}

// Space and Enter activate a focused toggle with the same state, signal, and command contract as a click.
#test
{
    var host: Testing.HeadlessHost
    host.setup(180, 120)
    defer host.shutdown()
    host.recordCommands()
    iconButtonHeadlessReset()

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40}, IconButtonHeadless_Command, .Toggle)
    btn.sigCheckedChanged += &iconButtonHeadlessChecked
    host.focus(btn)

    host.keyPress(Input.Key.Space)
    @assert(btn.isChecked)
    host.keyPress(Input.Key.Return)
    @assert(!btn.isChecked)
    @assert(IconButtonHeadlessCheckCount == 2)
    @assert(host.commandCount == 2 and host.lastCommand == IconButtonHeadless_Command)
}

// Number of pixels painted in one exact color.
func iconButtonColorCount(image: const *Image, color: Color)->s32
{
    var result = 0
    for y in cast(s32) image.height
    {
        for x in cast(s32) image.width
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
// Under a railed palette the two indicator-less placements shared a branch with the default one
// and got a rule in the accent along their bottom edge. That rule is how a tool rail marks the
// tool in use; drawn under a color swatch, a field of a form, or a preset cell painted in the
// user's own colors, it reads as one more thing painted in the cell.
#test
{
    var host: Testing.HeadlessHost
    host.setup(80, 80)
    defer host.shutdown()
    host.theme.setSwagDark()     // a palette that marks the active item with a rail
    host.notify(.ThemeChanged)

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40}, flags: .Toggle)
    btn.setForm(.Rectangle)
    btn.setChecked(true)

    let rail = host.theme.colors.activeRail
    @assert(rail.a != 0)

    for indicator in [IconButtonCheckIndicator.None, .Ink]
    {
        btn.setCheckIndicator(indicator)
        host.finishAnimations()
        var image = host.render()
        @assert(iconButtonColorCount(&image, rail) == 0)
    }

    for indicator in [IconButtonCheckIndicator.Bottom, .Top, .Left, .Right, .Full]
    {
        btn.setCheckIndicator(indicator)
        host.finishAnimations()
        var image = host.render()
        @assert(iconButtonColorCount(&image, rail) > 0)
    }

    btn.setCheckIndicator(.Frame)
    host.finishAnimations()
    var framed = host.render()
    let border = host.theme.colors.btnIcon_CheckedFrameBorder
    @assert(iconButtonColorCount(&framed, border) > 0)
}

// The checked frame is drawn on the shape the active palette gives the button.
//
// A rectangular tool is slightly rounded in every palette. The frame and focus ring have to
// follow that corner, or either mark crosses the fill at the corners.
#test
{
    var host: Testing.HeadlessHost
    host.setup(80, 80)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40}, flags: .Toggle)
    btn.setCheckIndicator(.Frame)
    btn.setChecked(true)

    let border = host.theme.colors.btnIcon_CheckedFrameBorder

    // An explicitly rounded tool cuts its own corner.
    btn.setForm(.RoundedRectangle)
    host.finishAnimations()
    var rounded = host.render()
    @assert(iconButtonColorCount(&rounded, border) > 0)
    @assert(btn.focusRingRadius == host.theme.rects.btnIcon_RoundSquareBk.radius)
    @assert(rounded.pixelColor(20, 20) != border)

    // The palette gives a rectangular tool the same slight corner.
    btn.setForm(.Rectangle)
    host.finishAnimations()
    var softened = host.render()
    @assert(btn.focusRingRadius == host.theme.rects.btnIcon_SquareBk.radius)
    @assert(softened.pixelColor(20, 20) != border)

    // Both neutral palettes keep the slight corner and the marks follow it.
    for light in [false, true]
    {
        if light do
            host.theme.setLight()
        else do
            host.theme.setDark()
        host.notify(.ThemeChanged)
        host.finishAnimations()

        var neutral       = host.render()
        let neutralBorder = host.theme.colors.btnIcon_CheckedFrameBorder
        @assert(btn.focusRingRadius == host.theme.rects.btnIcon_RoundSquareBk.radius)
        @assert(neutral.pixelColor(20, 20) != neutralBorder)
        @assert(iconButtonColorCount(&neutral, neutralBorder) > 0)
    }
}

// A framed checked tool keeps an accent glyph when the palette changes to light.
//
// Filled selections use the inverse ink of their accent fill. A framed selection has only a
// neutral wash, so carrying that inverse ink over made its glyph white on the light palette.
#test
{
    var host: Testing.HeadlessHost
    host.setup(80, 80)
    defer host.shutdown()

    let btn = IconButton.create(&host.root, host.theme.icon(.Filter, 24), {20, 20, 40, 40}, flags: .Toggle)
    btn.setCheckIndicator(.Frame)
    btn.setChecked(true)

    for light in [false, true]
    {
        if light do
            host.theme.setLight()
        else do
            host.theme.setSwagDark()
        host.notify(.ThemeChanged)
        host.finishAnimations()

        var image = host.render()
        let mark  = host.theme.colors.btnIcon_CheckedMark
        @assert(iconButtonColorCount(&image, mark) > 0)
        if light do
            @assert(mark != Argb.White)
    }
}

// The two indicator-less placements differ by what they leave the state colors saying: `None`
// reads as pressed, `Ink` keeps the checked ink so the glyph itself carries the state.
#test
{
    var host: Testing.HeadlessHost
    host.setup(80, 80)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40}, flags: .Toggle)
    btn.setForm(.Rectangle)
    btn.setChecked(true)

    let colors = host.theme.colors

    btn.setCheckIndicator(.None)
    host.finishAnimations()
    var pressed = host.render()
    @assert(iconButtonColorCount(&pressed, colors.btnIcon_CheckedPressedBk) > 0)

    btn.setCheckIndicator(.Ink)
    host.finishAnimations()
    var ink = host.render()
    @assert(iconButtonColorCount(&ink, colors.btnIcon_CheckedPressedBk) == 0)
}

// Hiding a button resets both its pointer state and its animated overlay state.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)
    defer host.shutdown()
    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40})
    btn.isHot          = true
    btn.isPressed      = true
    btn.aniBk.themeCrc = 42'u32

    btn.hide()

    @assert(!btn.isHot)
    @assert(!btn.isPressed)
    @assert(btn.aniBk.themeCrc == Swag.U32.Max)
}

// Disabling a button keeps it in the layout, but still drops transient input/paint state.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 120)
    defer host.shutdown()
    let btn = IconButton.create(&host.root, {}, {20, 20, 40, 40})
    btn.isHot              = true
    btn.isIn               = true
    btn.isPressed          = true
    btn.isPressing         = true
    btn.aniBk.themeCrc     = 42'u32
    host.app.mouseEnterWnd = btn
    host.app.setMouseCaptureRaw(btn)

    btn.disable()

    @assert(!btn.isHot)
    @assert(!btn.isIn)
    @assert(!btn.isPressed)
    @assert(!btn.isPressing)
    @assert(btn.aniBk.themeCrc == Swag.U32.Max)
    @assert(host.app.mouseEnterWnd == null)
    @assert(host.app.mouseCaptureWnd == null)
}

// An icon button answers what its content needs, so a longer wording widens the button
// instead of being crowded by it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()

    let icon = host.root.theme().icon(ThemeIcons.Play, 18)
    let btn  = IconButton.create(&host.root, icon, {0, 0, 80, 30}, IconButtonHeadless_Command)
    btn.setText("Save")
    btn.setTextPosition(.Right)

    let short = btn.itf.measureContent({320, 200})
    btn.setText("Enregistrer sous")
    let long = btn.itf.measureContent({320, 200})
    @assert(long.x > short.x)
    @assert(long.y == short.y)

    // Stacked, the same wording grows the other axis instead.
    btn.setTextPosition(.Bottom)
    let stacked = btn.itf.measureContent({320, 200})
    @assert(stacked.y > short.y)

    // A button hiding its label answers for the icon alone, whatever the wording is.
    btn.updateFlags(.IconOnly)
    let hidden = btn.itf.measureContent({320, 200})
    btn.setText("A much longer caption nobody sees")
    @assert(btn.itf.measureContent({320, 200}).x == hidden.x)
}
