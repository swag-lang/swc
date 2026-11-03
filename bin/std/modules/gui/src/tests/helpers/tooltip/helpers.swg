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
