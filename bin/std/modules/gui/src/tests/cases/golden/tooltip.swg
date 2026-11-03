#global if #command == Swag.CompilerCommand.Test
#global internal

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
        Swag.assert(not (wnd is ScrollWnd))
        Swag.assert(not (wnd is RichEditCtrl))
        Swag.assert(wnd.focusPolicy == .None)
    }

    // The text fits the box the tip committed, on both axes.
    let need = label.measure(Math.Point{label.position.width, 0}).preferred
    Swag.assert(need.x <= label.position.width)
    Swag.assert(need.y <= label.position.height)

    // Inside both caps: the one the theme sets, and the window that has to show it.
    let metrics = tip.themeMetrics()
    let parent  = unwrap tip.parent
    Swag.assert(tip.position.width <= metrics.toolTip_MaxWidth)
    Swag.assert(tip.position.height <= metrics.toolTip_MaxHeight)
    Swag.assert(tip.position.x >= 0 and tip.position.y >= 0)
    Swag.assert(tip.position.right() <= parent.position.width)
    Swag.assert(tip.position.bottom() <= parent.position.height)
}

// Shows a tip immediately and returns the label it built.
func showTip(owner: *Wnd, text: string)->*Label
{
    ToolTip.show(owner, {40, 40}, text, 0's)
    return assume cast (*Label, owner.app().toolTip.current!.view)
}

// Returns an annotation far taller than any tip may grow.
func longAnnotation()->String
{
    var result: #returntype
    for 40 do
        result += "every sentence adds another line to this annotation. "
    return result
}

// A tip holding one short line is exactly as large as that line, and shows nothing else.

// A tip longer than the width cap wraps instead of growing, and still holds all of its text.

// The history label that exposed the clipping bug keeps one physical pixel beyond its measured
// run at fractional DPI, so the accented final glyph cannot land on the half-open clip edge.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 200, 1.5)

    let btn = PushButton.create(&host.root, "Files", {20, 20, 100, 30})
    let lbl = showTip(btn, "Fichiers à côté de celui-ci")
    let tip = unwrap host.app.toolTip.current
    assertPassiveAndFits(tip, lbl)

    Swag.assert(lbl.maxLines == 0)

    let rendered = host.renderSettled(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&rendered, "tooltip.history-fractional")
}

// A tip taller than the height cap stops there and marks its last line, rather than scrolling.

// A window smaller than the theme's caps bounds the tip too, rather than shoving it back inside.

var g_LinkOwner: *Wnd?
var g_LinkText:  String

// A tip carrying a link is reachable, keeps its markup colors, and says which owner it came from.

// A tip with nothing to click stays out of the way: the pointer reaching it ends it.

// A tip belongs to its application, so one left open cannot reach the next application.
//
// The state used to be held per process, and a test that ended with a tip on screen handed a live
// window — parented to a surface that had just gone — to whatever ran next. Neither host here
// tears its tip down on purpose; the second one must still start empty.

// The shapes a tip can take, rendered.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(460, 320)

    let btn = PushButton.create(&host.root, "Library", {20, 20, 100, 30})

    discard showTip(btn, "Refresh")
    let short = host.renderSettled(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&short, "tooltip.short")

    discard showTip(btn, "Afficher la bibliothèque de captures et retrouver les images enregistrées pendant la session")
    let wrapped = host.renderSettled(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&wrapped, "tooltip.wrapped")

    let long = longAnnotation()
    discard showTip(btn, long.toString())
    let truncated = host.renderSettled(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&truncated, "tooltip.truncated")

    discard showTip(btn, "Read <b>the guide</b> at <url>swag-lang.org</url>, or ask on <p1>Discord</p>")
    let rich = host.renderSettled(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&rich, "tooltip.rich")
}
