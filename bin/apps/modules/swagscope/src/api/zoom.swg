#global public
#global namespace Viewer

using Core, Gui

// The text zoom every reading viewer offers, in percent: its range, and the notch a key or a
// wheel step moves it by.
const MinZoom  = 50'u32
const MaxZoom  = 300'u32
const ZoomStep = 25'u32

// The zoom button of an information group: its width, the inset on each side, and the slot
// both take in the group.
const ZoomButtonWidth = 72.0
const ZoomButtonInset = 12.0
const ZoomSlotWidth   = ZoomButtonWidth + 2 * ZoomButtonInset

// Returns the label of a zoom level, as the information bar shows it.
func zoomText(percent: u32)->String => Format.toString("% %", percent, "%")

// Returns `percent` brought within the zoom range.
func clampZoom(percent: u32)->u32 => Math.clamp(percent, MinZoom, MaxZoom)

// Returns the zoom one notch above `percent`.
func zoomIn(percent: u32)->u32 => clampZoom(percent + ZoomStep)

// Returns the zoom one notch below `percent`, never under the range.
func zoomOut(percent: u32)->u32 => percent > MinZoom + ZoomStep ? percent - ZoomStep : MinZoom

// Creates the zoom readout a viewer shows in its information group `info`: a menu button that reads
// the level in use, `100 %` until the viewer sets one. The caller connects what pressing it does.
func createZoomButton(info: *Wnd, id, toolTip: string, width = ZoomButtonWidth)->*IconButton
{
    with let result = IconButton.create(info, {}, {0, 0, width, 32}, id, .CenterContent)
    {
        .dockStyle = .Center
        .margin    = {ZoomButtonInset, 0, ZoomButtonInset, 0}
        .toolTip   = toolTip
        .setText(zoomText(100))
        .setArrowPosition(.RightDownward)
        .setForm(.Rectangle)
        .style.setFont(result.theme().createDefaultFontFs(11), .Regular)
    }

    return result
}

// Reports whether `key` is a zoom shortcut: Ctrl with plus or minus steps the zoom, Ctrl with 0
// resets it.
func isZoomKey(key: const *KeyEvent)->bool
{
    if key.kind != .Pressed or not key.modifiers.has(.Control) do
        return false
    switch key.key
    {
    case .Add, .OemPlus, .Subtract, .OemMinus, .D0: return true
    default: return false
    }
}

// Returns the zoom the shortcut `key` asks for from `percent`.
func zoomAfterKey(key: const *KeyEvent, percent: u32)->u32
{
    switch key.key
    {
    case .Add, .OemPlus:       return zoomIn(percent)
    case .Subtract, .OemMinus: return zoomOut(percent)
    default: return 100
    }
}

// One level of the zoom menu: its percentage, its label, and its menu identifier.
private struct ZoomPreset
{
    percent: u32
    label:   string
    id:      string
}

private const ZoomPresets: [5] ZoomPreset = [
    {75,  "75%",  "scope.zoom75"},
    {100, "100%", "scope.zoom100"},
    {125, "125%", "scope.zoom125"},
    {150, "150%", "scope.zoom150"},
    {200, "200%", "scope.zoom200"}]

// Shows the zoom menu of a reading viewer under `anchor`, with the level in use checked, and
// returns the level the reader picked, or 0 when the menu closed without a choice.
func pickZoom(owner: *Wnd, anchor: *IconButton, current: u32)->u32
{
    let menu = MenuCtrl.createPopup(owner, owner: owner)
    for preset in ZoomPresets do
        menu.addItem(preset.label, preset.id, checked: preset.percent == current)

    let chosen = menu.doModal(anchor, autoDestroy: true) orelse ""
    for preset in ZoomPresets where preset.id == chosen do
        return preset.percent
    return 0
}
