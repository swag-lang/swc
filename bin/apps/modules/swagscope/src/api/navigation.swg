#global public
#global namespace Viewer

using Core, Gui

// Width reserved for a page counter, independent of its current number of digits.
const PageReadoutWidth = 96.0

// Returns the width of the previous, current/total and next group.
func pageControlWidth(metrics: const *ThemeMetrics)->f32 => 2 * themeActionButtonSize(metrics) + PageReadoutWidth

// Formats a zero-based page index and its total; an empty document reads 0 / 0.
func pageText(index, count: u64)->String => Format.toString("% / %", count ? Math.min(index + 1, count) : 0, count)

// Returns the page direction requested by Ctrl Page Up/Down, or zero for another key.
func pageKeyDirection(key: const *KeyEvent)->s32
{
    if key.kind != .Pressed or key.modifiers != .Control do
        return 0
    switch key.key
    {
    case .PageUp:   return -1
    case .PageDown: return 1
    default:        return 0
    }
}

// Creates one page arrow; a negative direction means previous and a positive one means next.
func createPageStep(parent: *Wnd, direction: s32)->*IconButton
{
    with let result = createActionButton(parent, direction < 0 ? .ChevronLeft : .ChevronRight)
    {
        .dockStyle = .Left
        .toolTip   = direction < 0 ? appStrings().ui_PreviousPage : appStrings().ui_NextPage
    }

    return result
}

// Creates a page counter that opens a page chooser supplied by its caller.
// Read-only counters use a Label with the same cell and fixed-width face.
func createPageReadout(parent: *Wnd, id: WndId, toolTip: string)->*IconButton
{
    let height      = themeActionButtonSize(parent.themeMetrics())
    with let result = IconButton.create(parent, {}, {0, 0, PageReadoutWidth, height}, id, .CenterContent)
    {
        .dockStyle = .Left
        .toolTip   = toolTip
        .setForm(.Rectangle)
        .setArrowPosition(.RightUpward)
        .style.setFont(parent.theme().createDefaultFontFs(12), .Regular)
    }

    return result
}

// Creates a read-only page counter, visually distinct from a counter that opens a chooser.
func createPageLabel(parent: *Wnd)->*Label
{
    with let result = Label.create(parent, "", {0, 0, PageReadoutWidth, themeActionButtonSize(parent.themeMetrics())}, null, .SecondaryText)
    {
        .dockStyle = .Left
        .style.setFont(parent.theme().createDefaultFontFs(12), .Regular)
        .setTextAlignment(.Center, .OpticalCenter)
    }

    return result
}
