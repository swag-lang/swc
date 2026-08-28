#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Collects the whole tip tree, so a test can state what a tip may never contain.
func collectTree(wnd: *Wnd, result: *Array'(*Wnd))
{
    result.add(wnd)
    for child in wnd.children do
        collectTree(child, result)
}

// Asserts the shared contract of every tip: a passive box holding its text whole.
//
// The two go together. A tip that scrolls hides part of what it was asked to say, and the box
// that grew a scroll bar is exactly the one whose text stopped fitting — so a test that checks
// only one of them passes while the other is broken.
func assertPassiveAndFits(tip: *FrameWnd, label: *Label)
{
    var tree: Array'(*Wnd)
    collectTree(tip, &tree)

    // No viewport, no editable field, and no stop the keyboard traversal could land on.
    for wnd in tree
    {
        @assert(wnd.type != ScrollWnd)
        @assert(wnd.type != RichEditCtrl)
        @assert(wnd.focusPolicy == FocusPolicy.None)
    }

    // The text fits the box the tip committed, on both axes.
    let need = label.measure({label.position.width, 0}).preferred
    @assert(need.x <= label.position.width)
    @assert(need.y <= label.position.height)

    // Inside both caps: the one the theme sets, and the window that has to show it.
    let metrics = tip.themeMetrics()
    let parent  = tip.parent!
    @assert(tip.position.width <= metrics.toolTip_MaxWidth)
    @assert(tip.position.height <= metrics.toolTip_MaxHeight)
    @assert(tip.position.x >= 0 and tip.position.y >= 0)
    @assert(tip.position.right() <= parent.position.width)
    @assert(tip.position.bottom() <= parent.position.height)
}

// Shows a tip immediately and returns the label it built.
func showTip(owner: *Wnd, text: string)->*Label
{
    ToolTip.show(owner, {40, 40}, text, 0's)
    return cast(*Label) owner.app().toolTip.current!.view
}

// A tip holding one short line is exactly as large as that line, and shows nothing else.
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 200)
    defer host.shutdown()

    let btn = PushButton.create(&host.root, "Refresh", {20, 20, 100, 30})
    let lbl = showTip(btn, "Refresh")

    let tip = host.app.toolTip.current!
    assertPassiveAndFits(tip, lbl)

    // Nothing was dropped, so no line budget was needed and the text is intact.
    @assert(lbl.maxLines == 0)
    @assert(lbl.text() == "Refresh")

    // One line of text, plus the tip's own inset, and no room spent on anything else.
    let metrics = host.root.themeMetrics()
    let line    = lbl.font().regular!.height
    @assert(tip.position.height <= Math.ceil(line + metrics.toolTip_Padding.y + metrics.toolTip_Padding.w))
}

// A tip longer than the width cap wraps instead of growing, and still holds all of its text.
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 300)
    defer host.shutdown()

    let btn = PushButton.create(&host.root, "Library", {20, 20, 100, 30})
    let lbl = showTip(btn, "Afficher la bibliothèque de captures et retrouver les images enregistrées pendant la session")

    let tip = host.app.toolTip.current!
    assertPassiveAndFits(tip, lbl)

    // Wrapped, not cut: several lines tall, and no budget was imposed.
    let line = lbl.font().regular!.height
    @assert(tip.position.height > line * 1.5)
    @assert(lbl.maxLines == 0)
}

// The history label that exposed the clipping bug keeps one physical pixel beyond its measured
// run at fractional DPI, so the accented final glyph cannot land on the half-open clip edge.
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 200, 1.5)
    defer host.shutdown()

    let btn = PushButton.create(&host.root, "Files", {20, 20, 100, 30})
    let lbl = showTip(btn, "Fichiers à côté de celui-ci")
    let tip = host.app.toolTip.current!
    assertPassiveAndFits(tip, lbl)

    @assert(lbl.maxLines == 0)

    host.settleAnimations(&host.surfaceWnd)
    let rendered = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&rendered, "tooltip.history-fractional")
}

// A tip taller than the height cap stops there and marks its last line, rather than scrolling.
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 400)
    defer host.shutdown()

    var long: String
    for 40 do
        long += "every sentence adds another line to this annotation. "

    let btn = PushButton.create(&host.root, "Help", {20, 20, 100, 30})
    let lbl = showTip(btn, long.toString())

    let tip = host.app.toolTip.current!
    assertPassiveAndFits(tip, lbl)

    // The height cap bit, so the label carries the line budget that produces the ellipsis.
    let metrics = host.root.themeMetrics()
    @assert(lbl.maxLines > 1)
    @assert(tip.position.height > metrics.toolTip_MaxHeight - lbl.font().regular!.height)
}

// A window smaller than the theme's caps bounds the tip too, rather than shoving it back inside.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 110)
    defer host.shutdown()

    var long: String
    for 40 do
        long += "every sentence adds another line to this annotation. "

    let btn = PushButton.create(&host.root, "Help", {10, 10, 60, 24})
    let lbl = showTip(btn, long.toString())

    assertPassiveAndFits(host.app.toolTip.current!, lbl)
}

var g_LinkOwner: #null *Wnd
var g_LinkText:  String

// A tip carrying a link is reachable, keeps its markup colors, and says which owner it came from.
#test
{
    var host: Testing.HeadlessHost
    host.setup(460, 220)
    defer host.shutdown()

    let btn = PushButton.create(&host.root, "Docs", {20, 20, 100, 30})
    let lbl = showTip(btn, "Read <b>the guide</b> at <url>swag-lang.org</url> for the rest")

    assertPassiveAndFits(host.app.toolTip.current!, lbl)
    @assert(lbl.name.hasUrl)

    // The palette survived. A tip that painted its text with one explicit color would collapse
    // the link, the three markup slots and the plain ink into the same value.
    let colors = lbl.themeColors()
    @assert(colors.label_Text == colors.toolTip_Text)
    @assert(colors.url_Text == colors.toolTip_Link)
    @assert(colors.richColor1 == colors.toolTip_Rich1)
    @assert(colors.url_Text != colors.label_Text)

    // The pointer may rest on it, which is what makes the link clickable; leaving ends it.
    host.app.toolTip.pointerMoved(btn, lbl)
    @assert(host.app.toolTip.current != null)
    host.app.toolTip.pointerMoved(lbl, &host.root)
    @assert(host.app.toolTip.current == null)

    host.app.toolTip.sigLinkActivated += func(owner, link)
    {
        g_LinkOwner = owner
        g_LinkText  = link
    }

    let again = showTip(btn, "Read <url>swag-lang.org</url>")
    again.sigLinkActivated.call(again, "swag-lang.org")
    @assert(g_LinkOwner == btn)
    @assert(g_LinkText == "swag-lang.org")
}

// A tip with nothing to click stays out of the way: the pointer reaching it ends it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 200)
    defer host.shutdown()

    let btn = PushButton.create(&host.root, "Refresh", {20, 20, 100, 30})
    let lbl = showTip(btn, "Refresh")

    @assert(!lbl.name.hasUrl)
    host.app.toolTip.pointerMoved(btn, lbl)
    @assert(host.app.toolTip.current == null)
}

// A tip belongs to its application, so one left open cannot reach the next application.
//
// The state used to be held per process, and a test that ended with a tip on screen handed a live
// window — parented to a surface that had just gone — to whatever ran next. Neither host here
// tears its tip down on purpose; the second one must still start empty.
#test
{
    var first: Testing.HeadlessHost
    first.setup(420, 200)
    let btn = PushButton.create(&first.root, "Refresh", {20, 20, 100, 30})
    discard showTip(btn, "Refresh")
    @assert(first.app.toolTip.current != null)
    first.shutdown()

    var second: Testing.HeadlessHost
    second.setup(420, 200)
    defer second.shutdown()
    @assert(second.app.toolTip.current == null)
    @assert(second.app.toolTip.pending == null)
}

// The shapes a tip can take, rendered.
#test
{
    var host: Testing.HeadlessHost
    host.setup(460, 320)
    defer host.shutdown()

    let btn = PushButton.create(&host.root, "Library", {20, 20, 100, 30})

    discard showTip(btn, "Refresh")
    host.settleAnimations(&host.surfaceWnd)
    let short = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&short, "tooltip.short")

    discard showTip(btn, "Afficher la bibliothèque de captures et retrouver les images enregistrées pendant la session")
    host.settleAnimations(&host.surfaceWnd)
    let wrapped = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&wrapped, "tooltip.wrapped")

    var long: String
    for 40 do
        long += "every sentence adds another line to this annotation. "

    discard showTip(btn, long.toString())
    host.settleAnimations(&host.surfaceWnd)
    let truncated = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&truncated, "tooltip.truncated")

    discard showTip(btn, "Read <b>the guide</b> at <url>swag-lang.org</url>, or ask on <p1>Discord</p>")
    host.settleAnimations(&host.surfaceWnd)
    let rich = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&rich, "tooltip.rich")

    host.app.toolTip.hide()
}
