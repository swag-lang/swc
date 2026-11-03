#global if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core, Pixel

#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 200)

    let btn = PushButton.create(&host.root, "Refresh", {20, 20, 100, 30})
    let lbl = showTip(btn, "Refresh")

    let tip = unwrap host.app.toolTip.current
    assertPassiveAndFits(tip, lbl)

    // Nothing was dropped, so no line budget was needed and the text is intact.
    Swag.assert(lbl.maxLines == 0)
    Swag.assert(lbl.text() == "Refresh")

    // One line of text, plus the tip's own inset, and no room spent on anything else.
    let metrics = host.root.themeMetrics()
    let line    = lbl.font().regular!.height
    Swag.assert(tip.position.height <= Math.ceil(line + metrics.toolTip_Padding.y + metrics.toolTip_Padding.w))
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 300)

    let btn = PushButton.create(&host.root, "Library", {20, 20, 100, 30})
    let lbl = showTip(btn, "Afficher la bibliothèque de captures et retrouver les images enregistrées pendant la session")

    let tip = unwrap host.app.toolTip.current
    assertPassiveAndFits(tip, lbl)

    // Wrapped, not cut: several lines tall, and no budget was imposed.
    let line = lbl.font().regular!.height
    Swag.assert(tip.position.height > line * 1.5)
    Swag.assert(lbl.maxLines == 0)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 400)

    let long = longAnnotation()
    let btn  = PushButton.create(&host.root, "Help", {20, 20, 100, 30})
    let lbl  = showTip(btn, long.toString())

    let tip = unwrap host.app.toolTip.current
    assertPassiveAndFits(tip, lbl)

    // The height cap bit, so the label carries the line budget that produces the ellipsis.
    let metrics = host.root.themeMetrics()
    Swag.assert(lbl.maxLines > 1)
    Swag.assert(tip.position.height > metrics.toolTip_MaxHeight - lbl.font().regular!.height)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 110)

    let long = longAnnotation()
    let btn  = PushButton.create(&host.root, "Help", {10, 10, 60, 24})
    let lbl  = showTip(btn, long.toString())

    assertPassiveAndFits(unwrap host.app.toolTip.current, lbl)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(460, 220)

    let btn = PushButton.create(&host.root, "Docs", {20, 20, 100, 30})
    let lbl = showTip(btn, "Read <b>the guide</b> at <url>swag-lang.org</url> for the rest")

    assertPassiveAndFits(unwrap host.app.toolTip.current, lbl)
    Swag.assert(lbl.name.hasUrl)

    // The palette survived. A tip that painted its text with one explicit color would collapse
    // the link, the three markup slots and the plain ink into the same value.
    let colors = lbl.themeColors()
    Swag.assert(colors.label_Text == colors.toolTip_Text)
    Swag.assert(colors.url_Text == colors.toolTip_Link)
    Swag.assert(colors.richColor1 == colors.toolTip_Rich1)
    Swag.assert(colors.url_Text != colors.label_Text)

    // The pointer may rest on it, which is what makes the link clickable; leaving ends it.
    host.app.toolTip.pointerMoved(btn, lbl)
    Swag.assert(host.app.toolTip.current != null)
    host.app.toolTip.pointerMoved(lbl, &host.root)
    Swag.assert(host.app.toolTip.current == null)

    host.app.toolTip.sigLinkActivated += func(owner, link)
    {
        g_LinkOwner = owner
        g_LinkText  = link
    }

    let again = showTip(btn, "Read <url>swag-lang.org</url>")
    again.sigLinkActivated.call(again, "swag-lang.org")
    Swag.assert(g_LinkOwner == btn)
    Swag.assert(g_LinkText == "swag-lang.org")
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 200)

    let btn = PushButton.create(&host.root, "Refresh", {20, 20, 100, 30})
    let lbl = showTip(btn, "Refresh")

    Swag.assert(not lbl.name.hasUrl)
    host.app.toolTip.pointerMoved(btn, lbl)
    Swag.assert(host.app.toolTip.current == null)
}
#test
{
    var first: Testing.HeadlessHost
    first.setup(420, 200)
    let btn = PushButton.create(&first.root, "Refresh", {20, 20, 100, 30})
    discard showTip(btn, "Refresh")
    Swag.assert(first.app.toolTip.current != null)
    first.shutdown()

    var second: Testing.HeadlessHost
    second.setup(420, 200)
    Swag.assert(second.app.toolTip.current == null)
    Swag.assert(second.app.toolTip.pending == null)
}
