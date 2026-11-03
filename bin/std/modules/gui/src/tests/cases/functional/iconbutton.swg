#global if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core, Pixel

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
