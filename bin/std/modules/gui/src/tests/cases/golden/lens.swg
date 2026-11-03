#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// French source links remain legible beside a checkable result in a narrow lens.
#[Swag.TestTag("golden")]
#test
{
    let light = false
    var host: Testing.HeadlessHost
    host.setup(480, 560)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    expect host.app.setLanguage("fr")
    let lens = lensSetup(&host)
    lens.addSource(.File, func(_) {})
    lens.open("center")
    Swag.assert(lens.chosenEntry()!.checked)
    var image = host.renderSettled(&host.root)
    Pixel.Testing.assertImageGolden(&image, light ? "lens.narrow.fr.paper" : "lens.narrow.fr.ink")
    host.click(lensFooterActionPosition(lens))
    Swag.assert(lens.results.prefix == .Action and lens.results.query == "center")
}

// The lens over a document, with lines, a command family and the keys at its foot, in Papier.
#[Swag.TestTag("golden")]
#test
{
    let light = true
    var host: Testing.HeadlessHost
    host.setup(800, 560)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    with let document = Label.create(&host.root, "impl ViewerActionBar\n{\n    func create(parent: *Wnd)->*ViewerActionBar\n    {\n        with let result = Wnd.create'ViewerActionBar(parent)\n    }\n}", {120, 60, 600, 400})
    {
        .style.setFont(host.theme.createDefaultFontFamilyFs(14))
        .setTextAlignment(.Left, .Top)
    }

    let lens = lensSetup(&host)
    lens.open("center")
    host.keyPress(.Down)

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, light ? "lens.paper" : "lens.ink")
}

// The lens with a row of segments, the keys on a segment beside the one in force, in Encre and
// in Papier.
#[Swag.TestTag("golden")]
#test
{
    let light  = false
    var chosen = Swag.U64.Max
    var host: Testing.HeadlessHost
    host.setup(800, 680)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    with let document = Label.create(&host.root, "impl ViewerActionBar\n{\n    func create(parent: *Wnd)->*ViewerActionBar\n    {\n        with let result = Wnd.create'ViewerActionBar(parent)\n    }\n}", {120, 60, 600, 400})
    {
        .style.setFont(host.theme.createDefaultFontFamilyFs(14))
        .setTextAlignment(.Left, .Top)
    }

    let lens = lensSetup(&host)
    lens.addSource(.None, func|chosen = &chosen|(results) { addViewAsSection(results, chosen) })
    lens.open("center")
    for 3 do
        host.keyPress(.Down)
    host.keyPress(.Left)

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, light ? "lens.inline.paper" : "lens.inline.ink")
}

// The foot teaches Ctrl Enter on a setting, in Encre.
#[Swag.TestTag("golden")]
#test
{
    let light = true
    var host: Testing.HeadlessHost
    host.setup(800, 480)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    let lens = lensSetup(&host)
    lens.open(">")
    for 2 do
        host.keyPress(.Down)

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, light ? "lens.stay.paper" : "lens.stay.ink")
}

// Overflow has visible pointer controls; the last page is reachable and filtering resets it.
#[Swag.TestTag("golden")]
#test
{
    let light = false
    var host: Testing.HeadlessHost
    host.setup(480, 560, 1.25)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    let lens = lensSetup(&host)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    lens.addSource(.Action, func(results)
    {
        if results.query.count != 0 do
            return
        let section = results.addSection("Results")
        for index in 20 do
            section.addEntry(Format.toString("Result %", index + 1))
    })
    lens.open(">")
    Swag.assert(lens.input.name.raw == strings().lens_Placeholder)
    Swag.assert(lens.nextPage.isVisible() and lens.nextPage.isEnabled())
    Swag.assert(lens.previousPage.isVisible() and not lens.previousPage.isEnabled())
    var image = host.renderSettled(&host.root)
    Pixel.Testing.assertImageGolden(&image, light ? "lens.overflow.paper" : "lens.overflow.ink")
    for 10
    {
        if not lens.nextPage.isEnabled() do
            break
        host.clickWnd(lens.nextPage)
    }

    Swag.assert(lens.scroll > 0 and lens.previousPage.isEnabled() and not lens.nextPage.isEnabled())
    Swag.assert(host.app.keyboardFocusWnd == &lens.input.wnd)
    host.clickWnd(lens.previousPage)
    Swag.assert(lens.nextPage.isEnabled())
    host.root.resize(800, 2400)
    lens.itf.onLayout()
    Swag.assert(lens.scroll == 0 and not lens.nextPage.isVisible())
    host.root.resize(480, 560)
    lens.itf.onLayout()
    lens.setQuery(">save")
    Swag.assert(lens.scroll == 0 and not lens.nextPage.isVisible())

    // The reset sits immediately before the available source links and keeps the typed words.
    let metrics     = lens.themeMetrics()
    let font        = lens.theme().createDefaultFont(metrics.hintLine_FontSize)
    let action      = lensFooterActionPosition(lens)
    let right       = lens.clientRect().horzCenter() + Math.min(metrics.lens_Width, lens.clientRect().width - 2 * metrics.floating_Inset) * 0.5 - metrics.lens_TextInset
    let actionWidth = keycapWidth(lens, ">") + metrics.hintLine_KeyGap + Painter.measureString(strings().lens_Actions, font).width
    let lineWidth   = keycapWidth(lens, ":") + metrics.hintLine_KeyGap + Painter.measureString(strings().lens_Line, font).width
    let allWidth    = Painter.measureString(strings().lens_All, font).width
    var reset       = Math.Point{right - actionWidth - lineWidth - 2 * metrics.hintLine_GroupGap - allWidth * 0.5, action.y}
    lens.surface!.surfaceToScreen(&reset)
    host.click(reset)
    Swag.assert(lens.query() == "save" and lens.results.prefix == .None)
}
