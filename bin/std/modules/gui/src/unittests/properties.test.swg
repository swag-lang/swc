#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core

struct PropHeadlessData
{
    count:      s32 = 42
    label:      string = "hello"
    enabled:    bool = true
}

struct PropHeadlessCustomData
{
    origin:     Math.Point = {10, 20}
    count:      s32 = 3
}

enum PropHeadlessChoice
{
    Low
    Mid
    High
}

struct PropHeadlessEnumData
{
    choice:     PropHeadlessChoice = .Mid
}

struct PropHeadlessSliderData
{
    #[SliderMinMax(0, 100)]
    volume:     s32 = 50

    #[SliderMinMax(0, 10)]
    level:      s32 = 5
}

struct PropHeadlessGroupedData
{
    #[Category("Numbers")]
    count:      s32 = 42

    label:      string = "hello"

    #[Category("Flags")]
    enabled:    bool = true
}

struct PropHeadlessRoData
{
    normal:     s32 = 1

    #[ReadOnly]
    locked:     s32 = 2

    dynamic:    s32 = 3
}

struct PropMoveElem
{
    id:         s32 = 0
}

struct PropMoveData
{
    dyn:        Array'PropMoveElem
    stat:       [3] s32
}

var g_PropRoDynamic: bool

impl IPropertyNotify for PropHeadlessRoData
{
    mtd impl isItemReadOnly(_list: *Properties, item: *PropertiesItem)->bool
    {
        if item.typeValue.name == #nameof(PropHeadlessRoData.dynamic) do
            return g_PropRoDynamic
        return false
    }
}

// Properties.addStruct reflects a struct into one item per field (+ a section item).
#test
{
    var host: GuiHeadlessHost
    host.setup(260, 320)

    var data: PropHeadlessData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    // 1 implicit section item + 3 fields.
    @assert(prop.items.count == 4)
    @assert(prop.items[0].flags.has(.Section))

    host.shutdown()
}

// PropertiesCtrl keeps visible grid rows after the same staged layout sequence
// used by the gui4 example: create at a placeholder height, add structs, then
// dock into its final parent.
#test
{
    var host: GuiHeadlessHost
    host.setup(1240, 820)

    let page = Wnd.create'Wnd(&host.root, {24, 104, 1192, 666})

    var data: PropHeadlessGroupedData
    let ctrl = PropertiesCtrl.create(page, {0, 0, 560, 10}, .Grid, .SectionFilter | .SectionPane | .FindBar)
    ctrl.dockStyle = .Left
    ctrl.margin.z = 24
    ctrl.prop.sizeEditValue = 300
    ctrl.prop.setColumnSize(150)
    ctrl.addStruct(data, "Settings")
    ctrl.splitter.setPaneSize(0, 160)
    ctrl.splitter.items[0].tryPreserveSize = true

    let preview = Wnd.create'FrameWnd(page, {})
    preview.dockStyle = .Center

    page.applyLayout()

    @assert(ctrl.position == Math.Rectangle{0, 0, 560, 666})
    @assert(ctrl.splitter.position.width > 0)
    @assert(ctrl.splitter.position.height > 0)
    @assert(ctrl.prop.position.width > 0)
    @assert(ctrl.prop.position.height > 0)
    @assert(ctrl.prop.edView.position.width > 0)
    @assert(ctrl.prop.edView.position.height > 0)
    @assert(ctrl.prop.items.count == 6)
    @assert(ctrl.prop.items[0].line.isVisible())
    @assert(ctrl.prop.items[1].line.isVisible())
    @assert(ctrl.prop.items[1].line.position.height == ctrl.prop.gridLineHeight)
    @assert(ctrl.prop.items[1].line.position.y >= ctrl.prop.gridLineHeight)

    host.shutdown()
}

// Keyboard navigation: focusNav selects the first navigable row, arrows move the
// highlight over the editable rows (clamped), Home/End jump to the ends.
#test
{
    var host: GuiHeadlessHost
    host.setup(260, 320)

    var data: PropHeadlessData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)        // [0]=section [1]=count [2]=label [3]=enabled

    prop.focusNav()
    @assert(prop.selItem == prop.items[1])      // section row is skipped
    @assert(host.app.keybFocusWnd == cast(*Wnd) prop.edView)

    host.keyPress(Input.Key.Down)
    @assert(prop.selItem == prop.items[2])
    host.keyPress(Input.Key.Down)
    @assert(prop.selItem == prop.items[3])
    host.keyPress(Input.Key.Down)               // clamp at the last row
    @assert(prop.selItem == prop.items[3])
    host.keyPress(Input.Key.Up)
    @assert(prop.selItem == prop.items[2])

    host.keyPress(Input.Key.Home)
    @assert(prop.selItem == prop.items[1])
    host.keyPress(Input.Key.End)
    @assert(prop.selItem == prop.items[3])

    host.shutdown()
}

// Enter starts editing the selected row (focuses its editor); Escape returns to
// navigation mode (focus back on the grid).
#test
{
    var host: GuiHeadlessHost
    host.setup(260, 320)

    var data: PropHeadlessData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    prop.focusNav()                              // selItem = count row
    host.keyPress(Input.Key.Return)
    @assert(host.app.keybFocusWnd == cast(*Wnd) prop.items[1].editBox)

    host.keyPress(Input.Key.Escape)
    @assert(host.app.keybFocusWnd == cast(*Wnd) prop.edView)

    host.shutdown()
}

// While editing, Up/Down auto-commit and move the selection back to navigation
// mode on the adjacent row.
#test
{
    var host: GuiHeadlessHost
    host.setup(260, 320)

    var data: PropHeadlessData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    prop.focusNav()                              // count row
    host.keyPress(Input.Key.Return)             // edit count
    @assert(host.app.keybFocusWnd == cast(*Wnd) prop.items[1].editBox)

    host.keyPress(Input.Key.Down)               // commit + move to label row
    @assert(prop.selItem == prop.items[2])
    @assert(host.app.keybFocusWnd == cast(*Wnd) prop.edView)

    host.shutdown()
}

// Tab commits the current edit and starts editing the next editable row.
#test
{
    var host: GuiHeadlessHost
    host.setup(260, 320)

    var data: PropHeadlessData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    prop.focusNav()
    host.keyPress(Input.Key.Return)             // edit count
    host.keyPress(Input.Key.Tab)                // -> edit label row
    @assert(prop.selItem == prop.items[2])
    @assert(host.app.keybFocusWnd == cast(*Wnd) prop.items[2].editBox)

    host.shutdown()
}

struct PropHeadlessActionData
{
    #[Description("Visible actions are listed in the preview footer.")]
    visible: bool = true
}

struct PropHeadlessArrayData
{
    origin:  Math.Point = {36, 46}
    actions: Array'PropHeadlessActionData
}

// In list mode each row is a vertical StackLayoutCtrl: the name label on top and the
// value editor stacked underneath. Editors that wrap their control in an inner line
// (bool, vector, array count) must not dock-center that line vertically, or it would
// overlap the name label. This asserts every value child sits fully below its label.
#test
{
    var host: GuiHeadlessHost
    host.setup(400, 600)

    var data: PropHeadlessArrayData
    data.actions.resize(1)
    let prop = Properties.create(&host.root, {0, 0, 380, 560}, .List)
    prop.addStruct(data, "S")
    prop.edView.sendResizeEvent()

    // items: [0]=section [1]=origin (vector) [2]=actions (array) [3]=element "0" [4]=visible (bool)
    @assert(prop.items[1].label != null and prop.items[2].label != null and prop.items[4].label != null)

    // For each value row, the inner value line must start at or below the label bottom.
    func assertBelowLabel(item: *PropertiesItem)
    {
        let labelBottom = item.label.position.bottom()
        foreach c in item.line.childs
        {
            if c == cast(*Wnd) item.label do
                continue
            @assert(c.position.y >= labelBottom)
        }
    }

    assertBelowLabel(prop.items[1])     // vector
    assertBelowLabel(prop.items[2])     // array count editor
    assertBelowLabel(prop.items[4])     // bool

    // The bool description is nudged down to optically center on the box: it carries a
    // positive top text padding derived from the font descent (never a hard-coded value).
    let chk  = prop.items[4].checkBox
    var desc: *Label
    foreach c in chk.parent.childs do
        if c != cast(*Wnd) chk do
            desc = cast(*Label) c
    @assert(desc != null)
    @assert(desc.paddingText.y > 0)
    @assert(Math.abs(desc.paddingText.y + desc.paddingText.w) < 0.01)   // pure translation, no height loss

    host.shutdown()
}

struct PropHeadlessColorData
{
    f0, f1, f2, f3, f4, f5, f6, f7: s32
    tint: Pixel.Color
    f8, f9, f10, f11, f12, f13: s32
}

// While an editor popup (e.g. the color picker) is open the grid is modal: mouse wheel
// events over the list are swallowed so it cannot scroll out from under the anchored
// popup. Clearing the popup restores scrolling.
#test
{
    var host: GuiHeadlessHost
    host.setup(300, 200)

    var data: PropHeadlessColorData
    let prop = Properties.create(&host.root, {0, 0, 280, 180}, .List)
    prop.addStruct(data, "S")
    prop.edView.sendResizeEvent()

    @assert(prop.scrollWnd.scrollSize.y > prop.position.height)         // content overflows -> scrollable

    func sendWheel(p: *Properties, deltaY: f32)
    {
        var wheel = MouseEvent{kind: .MouseWheel}
        wheel.move.y     = deltaY
        wheel.surfacePos = {20, 90}
        p.edView.sendEvent(&wheel)
    }

    // Control: with no popup, the wheel scrolls the list.
    let y0 = prop.scrollWnd.getScrollPos().y
    sendWheel(prop, -6)                                                 // scroll down
    let y1 = prop.scrollWnd.getScrollPos().y
    @assert(y1 != y0)

    // Modal: with a popup open, the same wheel is swallowed and the list stays put.
    let popup = Wnd.create'Wnd(&host.root, {})
    prop.editPopup = popup
    sendWheel(prop, -6)
    @assert(prop.scrollWnd.getScrollPos().y == y1)

    // Clearing the popup restores scrolling.
    prop.editPopup = null
    sendWheel(prop, 6)                                                  // scroll back up
    @assert(prop.scrollWnd.getScrollPos().y != y1)

    host.shutdown()
}

fileprivate func findIconButton(w: *Wnd)->#null *IconButton
{
    foreach c in w.childs
    {
        if c.type == IconButton do
            return cast(*IconButton) c
        let sub = findIconButton(c)
        if sub do
            return sub
    }
    return null
}

// The modal block must swallow only wheel events, not hover/leave: otherwise the popup
// trigger button never receives its MouseLeave and stays stuck in the hot state after
// the popup closes. A MouseLeave while the popup is open must still clear the button.
#test
{
    var host: GuiHeadlessHost
    host.setup(300, 200)

    var data: PropHeadlessColorData
    let prop = Properties.create(&host.root, {0, 0, 280, 180}, .List)
    prop.addStruct(data, "S")
    prop.edView.sendResizeEvent()

    let btn = findIconButton(prop.items[9].line)                        // the color swatch button
    @assert(btn != null)

    // Hover the button (no popup yet) -> hot.
    host.sendMouseEvent(btn, .MouseEnter, {0, 0}, .Left, .Zero)
    @assert(btn.isHot)

    // With a popup open, a MouseLeave must still reach the button and clear the hover.
    let popup = Wnd.create'Wnd(&host.root, {})
    prop.editPopup = popup
    host.sendMouseEvent(btn, .MouseLeave, {0, 0}, .Left, .Zero)
    @assert(!btn.isHot)

    host.shutdown()
}

// In navigation mode, Space toggles a bool row's checkbox in place.
#test
{
    var host: GuiHeadlessHost
    host.setup(260, 320)

    var data: PropHeadlessData          // enabled = true
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    prop.focusNav()
    host.keyPress(Input.Key.End)                // enabled (checkbox) row
    let chk = prop.items[3].checkBox
    @assert(chk != null)
    @assert(chk.isChecked())

    host.keyPress(Input.Key.Space)
    @assert(!chk.isChecked())
    host.keyPress(Input.Key.Space)
    @assert(chk.isChecked())

    host.shutdown()
}

// Navigating a slider row: Right steps the slider track and focuses it (auto-commit
// model), a further Right keeps stepping, Down commits and moves to the next row.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 220)

    var data: PropHeadlessSliderData        // volume=50, level=5
    let prop = Properties.create(&host.root, {0, 0, 300, 200})
    prop.addStruct(data, "S")               // [0]=section [1]=volume [2]=level
    prop.edView.sendResizeEvent()

    prop.focusNav()
    @assert(prop.selItem == prop.items[1])  // section is not navigable in list mode

    // The very first Right in navigation steps the slider and focuses it (so the
    // value changes immediately, not only on the second press).
    host.keyPress(Input.Key.Right)
    @assert(prop.items[1].sliderBox.getValue() > 50)
    @assert(data.volume > 50)
    @assert(host.app.keybFocusWnd == cast(*Wnd) prop.items[1].sliderBox.slider)

    // A further Right keeps stepping (now in edit mode on the focused slider).
    let v1 = prop.items[1].sliderBox.getValue()
    host.keyPress(Input.Key.Right)
    @assert(prop.items[1].sliderBox.getValue() > v1)

    // Down auto-commits and moves to the next row, back in navigation mode.
    host.keyPress(Input.Key.Down)
    @assert(prop.selItem == prop.items[2])
    @assert(host.app.keybFocusWnd == cast(*Wnd) prop.edView)

    host.shutdown()
}

// Enter on a slider row edits its value box like a plain editbox row: it focuses the
// inner EditBox and selects its text so the value can be typed over right away.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 220)

    var data: PropHeadlessSliderData        // volume=50, level=5
    let prop = Properties.create(&host.root, {0, 0, 300, 200})
    prop.addStruct(data, "S")               // [0]=section [1]=volume [2]=level
    prop.edView.sendResizeEvent()

    prop.focusNav()
    @assert(prop.selItem == prop.items[1])

    let edit = prop.items[1].sliderBox.edit
    @assert(edit != null)

    // Enter focuses the value box (not the slider track) and selects its whole text.
    host.keyPress(Input.Key.Return)
    @assert(host.app.keybFocusWnd == cast(*Wnd) edit)
    @assert(edit.selBeg == 0 and edit.selEnd == edit.text.length)
    @assert(edit.text.length > 0)

    host.shutdown()
}

// Editing an enum row: Enter focuses the combo, Left/Right change the selection
// (reaching the combo, not intercepted) and write back to the data.
#test
{
    var host: GuiHeadlessHost
    host.setup(300, 200)

    var data: PropHeadlessEnumData          // choice = Mid (index 1)
    let prop = Properties.create(&host.root, {0, 0, 280, 180})
    prop.addStruct(data, "E")               // [0]=section [1]=choice
    prop.edView.sendResizeEvent()

    prop.focusNav()
    @assert(prop.selItem == prop.items[1])
    let combo = prop.items[1].comboBox
    @assert(combo != null)
    @assert(combo.selectedIdx == 1)         // Mid

    // Enter opens the drop-down popup. The grid keeps the keyboard focus and forwards
    // the keys to the popup (so they never leak to page navigation outside the grid).
    host.keyPress(Input.Key.Return)
    @assert(combo.popup != null)
    @assert(host.app.keybFocusWnd == cast(*Wnd) prop.edView)

    let pview = cast(*PopupListView) combo.popup.scrollWnd.view
    @assert(pview.hotIdx == 1)              // highlight starts on the current value

    // Down moves the highlight only; the committed value stays until Enter.
    host.keyPress(Input.Key.Down)           // highlight Mid -> High
    @assert(pview.hotIdx == 2)
    @assert(combo.selectedIdx == 1)         // not committed yet
    @assert(data.choice == .Mid)

    // A per-frame mouse-move outside the popup must not wipe the keyboard highlight.
    host.sendMouseEvent(cast(*Wnd) pview, MouseEvent.Kind.MouseMove, {2, 2}, Input.MouseButton.Left, Input.KeyModifiers.Zero)
    @assert(pview.hotIdx == 2)

    // Enter commits the highlighted item (writes the data) and closes the edit.
    host.keyPress(Input.Key.Return)
    host.pump()
    @assert(combo.selectedIdx == 2)
    @assert(data.choice == .High)
    @assert(combo.popup == null)
    @assert(host.app.keybFocusWnd == cast(*Wnd) prop.edView)

    host.shutdown()
}

// A row with a custom/composite editor (e.g. a Math.Point) is navigable and can be
// activated: Enter focuses the first inner editor, Down auto-commits to the next row.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 200)

    var data: PropHeadlessCustomData
    let prop = Properties.create(&host.root, {0, 0, 300, 180})
    prop.addStruct(data, "C")               // [0]=section [1]=origin [2]=count
    prop.edView.sendResizeEvent()

    prop.focusNav()
    @assert(prop.selItem == prop.items[1])  // the custom 'origin' row is selectable

    host.keyPress(Input.Key.Return)         // edit -> focus the first inner editbox
    let f = host.app.keybFocusWnd
    @assert(f != null)
    @assert(f.type == EditBox)

    host.keyPress(Input.Key.Down)           // commit + move to the next row
    @assert(prop.selItem == prop.items[2])
    @assert(host.app.keybFocusWnd == cast(*Wnd) prop.edView)

    host.shutdown()
}

// focusNav keeps the already-selected row (so clicking a header/custom row does not
// jump the selection to the first item).
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 200)

    var data: PropHeadlessCustomData
    let prop = Properties.create(&host.root, {0, 0, 300, 180})
    prop.addStruct(data, "C")

    prop.selItem = prop.items[1]            // as if 'origin' was just clicked
    prop.focusNav()
    @assert(prop.selItem == prop.items[1])  // kept, not reset to the first row

    host.shutdown()
}

// A named section becomes the first item and is registered.
#test
{
    var host: GuiHeadlessHost
    host.setup(260, 320)

    var data: PropHeadlessData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data, "Settings")

    @assert(prop.items.count == 4)
    @assert(prop.items[0].flags.has(.Section))
    @assert(prop.sections.count == 1)

    host.shutdown()
}

// PropertiesCtrl grid keeps deterministic line and editor heights.
#test
{
    var host: GuiHeadlessHost
    host.setup(360, 180)

    var data: PropHeadlessData
    let ctrl = PropertiesCtrl.create(&host.root, {0, 0, 320, 120}, .Grid, .Zero)
    ctrl.addStruct(data, "Settings")
    ctrl.prop.edView.sendResizeEvent()

    @assert(ctrl.prop.items.count == 4)
    @assert(ctrl.prop.items[0].line.position.y == 6)
    @assert(ctrl.prop.items[1].line.position.y == 53)
    @assert(ctrl.prop.items[2].line.position.y == 100)
    @assert(ctrl.prop.items[3].line.position.y == 147)
    @assert(ctrl.prop.items[0].line.position.height == 35)
    @assert(ctrl.prop.items[1].line.position.height == 35)
    @assert(ctrl.prop.items[2].line.position.height == 35)
    @assert(ctrl.prop.items[3].line.position.height == 35)
    @assert(ctrl.prop.items[0].line.position.width > 0)

    let countItem = ctrl.prop.items[1]
    @assert(countItem.label.position == Math.Rectangle{0, 0, 150, 35})
    @assert(countItem.editBox.position.height == ctrl.prop.getThemeMetrics().editBox_Height)
    @assert(countItem.editBox.position.y == Math.round((countItem.line.position.height - countItem.editBox.position.height) * 0.5))
    @assert(ctrl.prop.scrollWnd.scrollSize.y > ctrl.prop.position.height)

    host.shutdown()
}

// Properties list keeps rows visible after being docked with a filter bar, as
// used by the second page of gui4.
#test
{
    var host: GuiHeadlessHost
    host.setup(1240, 820)

    let page = Wnd.create'Wnd(&host.root, {24, 104, 1192, 666})

    let filter = EditBox.create(page, "")
    filter.dockStyle = .Top
    filter.margin = {16, 16, 16, 4}

    var dataA: PropHeadlessGroupedData
    var dataB: PropHeadlessGroupedData
    var dataC: PropHeadlessGroupedData
    let prop = Properties.create(page, {}, .List)
    prop.dockStyle = .Center
    prop.margin = {16, 8, 16, 16}
    prop.addStruct(dataA, "Appearance")
    prop.addStruct(dataB, "Content")
    prop.addStruct(dataC, "Layout")

    page.applyLayout()

    @assert(prop.items.count == 18)
    @assert(prop.items[0].line.isVisible())
    @assert(prop.items[1].line.isVisible())
    @assert(prop.items[0].line.position.height > 0)
    @assert(prop.items[1].line.position.y > prop.items[0].line.position.y)
    @assert(prop.items[0].label.position.height > 0)
    @assert(prop.items[1].label.position.height > 0)
    @assert(prop.scrollWnd.scrollSize.y > prop.position.height)

    host.shutdown()
}

//
// Multi-selection editing: the grid edits several instances of the same struct at once.
//

enum MultiChoice
{
    Low
    Mid
    High
}

#[Swag.EnumFlags]
enum MultiBadges
{
    Star
    Lock
    Pin
}

struct MultiTile
{
    count:  s32 = 0
    flag:   bool = false
    name:   String
    choice: MultiChoice = .Low
    badges: MultiBadges
    tint:   Pixel.Color
    pos:    Math.Point = {0, 0}
}

fileprivate func findFieldItem(prop: *Properties, name: string)->#null *PropertiesItem
{
    foreach it in prop.items
    {
        if it.typeValue.name == name do
            return it
    }
    return null
}

// Edits applied through the grid write into every selected instance.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 360)

    var t0, t1, t2: MultiTile
    let prop = Properties.create(&host.root, {0, 0, 300, 340}, .List)

    var bases: Array'(*u8)
    bases.add(cast(*u8) &t0)
    bases.add(cast(*u8) &t1)
    bases.add(cast(*u8) &t2)
    prop.addStructMulti(MultiTile, bases.toSlice(), "S")
    prop.edView.sendResizeEvent()

    let countItem = findFieldItem(prop, "count")
    @assert(countItem != null)
    @assert(prop.instanceCount(countItem) == 3)
    @assert(!prop.fieldIsMixed(countItem))                  // all start equal (0)

    // Edit the native field: all three instances change together.
    countItem.editBox.setText("9")
    prop.validateNative(countItem)
    @assert(t0.count == 9 and t1.count == 9 and t2.count == 9)

    // Bool toggle propagates to all.
    let flagItem = findFieldItem(prop, "flag")
    flagItem.checkBox.toggle()
    @assert(t0.flag and t1.flag and t2.flag)

    // Enum selection propagates to all.
    let choiceItem = findFieldItem(prop, "choice")
    choiceItem.comboBox.selectItem(2)                       // High
    @assert(t0.choice == .High and t1.choice == .High and t2.choice == .High)

    host.shutdown()
}

// A field that differs across instances is "mixed": the editor shows no concrete value,
// and editing it resolves the field on every instance.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 360)

    var t0, t1: MultiTile
    t0.count = 1
    t1.count = 2                                            // differs -> mixed
    t0.flag  = true
    t1.flag  = false                                       // differs -> mixed

    let prop = Properties.create(&host.root, {0, 0, 300, 340}, .List)
    var bases: Array'(*u8)
    bases.add(cast(*u8) &t0)
    bases.add(cast(*u8) &t1)
    prop.addStructMulti(MultiTile, bases.toSlice(), "S")
    prop.edView.sendResizeEvent()

    let countItem = findFieldItem(prop, "count")
    @assert(prop.fieldIsMixed(countItem))
    @assert(countItem.editBox.getText() == "")             // blank when mixed

    let flagItem = findFieldItem(prop, "flag")
    @assert(prop.fieldIsMixed(flagItem))
    @assert(flagItem.checkBox.checked == .Undefined)       // indeterminate when mixed

    // Editing the mixed native field sets both instances and clears the mixed state.
    countItem.editBox.setText("7")
    prop.validateNative(countItem)
    @assert(t0.count == 7 and t1.count == 7)
    @assert(!prop.fieldIsMixed(countItem))
    @assert(countItem.editBox.getText() == "7")

    host.shutdown()
}

// A single instance behaves exactly like the classic addStruct (no multi state).
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 360)

    var t0: MultiTile
    t0.count = 3
    let prop = Properties.create(&host.root, {0, 0, 300, 340}, .List)
    var bases: Array'(*u8)
    bases.add(cast(*u8) &t0)
    prop.addStructMulti(MultiTile, bases.toSlice(), "S")
    prop.edView.sendResizeEvent()

    let countItem = findFieldItem(prop, "count")
    @assert(prop.instanceCount(countItem) == 1)
    @assert(!prop.fieldIsMixed(countItem))
    @assert(countItem.editBox.getText() == "3")

    countItem.editBox.setText("8")
    prop.validateNative(countItem)
    @assert(t0.count == 8)

    host.shutdown()
}

fileprivate func collectEditBoxes(w: *Wnd, out: *Array'(*EditBox))
{
    foreach c in w.childs
    {
        if c.type == EditBox do
            out.add(cast(*EditBox) c)
        collectEditBoxes(c, out)
    }
}

// Editing one vector component writes that component into every instance while leaving
// the other components (which may legitimately differ) untouched.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 380)

    var t0, t1: MultiTile
    t0.pos = {1, 10}
    t1.pos = {2, 10}                                        // x differs (mixed), y uniform

    let prop = Properties.create(&host.root, {0, 0, 300, 360}, .List)
    var bases: Array'(*u8)
    bases.add(cast(*u8) &t0)
    bases.add(cast(*u8) &t1)
    prop.addStructMulti(MultiTile, bases.toSlice(), "S")
    prop.edView.sendResizeEvent()

    let posItem = findFieldItem(prop, "pos")
    @assert(posItem != null)

    // x component differs -> mixed; y component is uniform -> not mixed.
    @assert(prop.subFieldIsMixed(posItem, 0, #sizeof(f32)))
    @assert(!prop.subFieldIsMixed(posItem, #sizeof(f32), #sizeof(f32)))

    var boxes: Array'(*EditBox)
    collectEditBoxes(posItem.line, &boxes)
    @assert(boxes.count == 2)                               // x and y

    // Set x = 5 on the first component box; both instances get x = 5, y is preserved.
    boxes[0].setText("5")
    boxes[0].sigLoseFocus.call(boxes[0])
    @assert(t0.pos.x == 5 and t1.pos.x == 5)
    @assert(t0.pos.y == 10 and t1.pos.y == 10)             // untouched
    @assert(!prop.subFieldIsMixed(posItem, 0, #sizeof(f32)))

    host.shutdown()
}

// Enum-flags multi-edit logic: a bit that disagrees across instances is "mixed", and
// setting one flag bit on every instance preserves the other (differing) bits. Exercised
// through the helpers directly because the EnumFlags attribute is not reflected in a
// test-mode build, so the flag rows would not be constructed here (they are in gui4).
#test
{
    var host: GuiHeadlessHost
    host.setup(200, 120)
    let prop = Properties.create(&host.root, {0, 0, 180, 100}, .List)

    var b0, b1: MultiBadges
    b0 = .Star
    b1 = MultiBadges.Star | MultiBadges.Lock               // Star shared, Lock only on b1

    var item: PropertiesItem
    item.type = MultiBadges
    item.dataInstances.add(cast(*u8) &b0)
    item.dataInstances.add(cast(*u8) &b1)

    let starMask = cast(u64) cast(s32) MultiBadges.Star
    let lockMask = cast(u64) cast(s32) MultiBadges.Lock
    let pinMask  = cast(u64) cast(s32) MultiBadges.Pin

    @assert(!prop.flagBitIsMixed(&item, starMask))         // shared -> uniform
    @assert(prop.flagBitIsMixed(&item, lockMask))          // disagrees -> mixed
    @assert(!prop.flagBitIsMixed(&item, pinMask))          // neither has it -> uniform

    // Set Pin on every instance: Lock stays only on b1, Star stays on both.
    prop.writeEnumBit(&item, pinMask, true)
    @assert(cast(bool) (b0 & MultiBadges.Pin) and cast(bool) (b1 & MultiBadges.Pin))
    @assert(!cast(bool) (b0 & MultiBadges.Lock))
    @assert(cast(bool) (b1 & MultiBadges.Lock))
    @assert(cast(bool) (b0 & MultiBadges.Star) and cast(bool) (b1 & MultiBadges.Star))

    // Clearing a shared bit clears it everywhere.
    prop.writeEnumBit(&item, starMask, false)
    @assert(!cast(bool) (b0 & MultiBadges.Star) and !cast(bool) (b1 & MultiBadges.Star))

    host.shutdown()
}

// Dynamic strings are compared and propagated by content (they own a heap buffer).
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 360)

    var t0, t1: MultiTile
    t0.name = "alpha"
    t1.name = "beta"                                       // differs -> mixed

    let prop = Properties.create(&host.root, {0, 0, 300, 340}, .List)
    var bases: Array'(*u8)
    bases.add(cast(*u8) &t0)
    bases.add(cast(*u8) &t1)
    prop.addStructMulti(MultiTile, bases.toSlice(), "S")
    prop.edView.sendResizeEvent()

    let nameItem = findFieldItem(prop, "name")
    @assert(nameItem != null)
    @assert(prop.fieldIsMixed(nameItem))
    @assert(nameItem.editBox.getText() == "")

    nameItem.editBox.setText("shared")
    prop.validateDynamicString(nameItem)
    @assert(t0.name == "shared" and t1.name == "shared")
    @assert(!prop.fieldIsMixed(nameItem))

    // Same content in distinct buffers must not read as mixed.
    t0.name = "same"
    t1.name = "same"
    @assert(!prop.fieldIsMixed(nameItem))

    host.shutdown()
}

// A color (struct via the built-in ColorEditor) reports mixed and propagates as a whole value.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 360)

    var t0, t1: MultiTile
    t0.tint = Pixel.Argb.Red
    t1.tint = Pixel.Argb.Blue                              // differs -> mixed

    let prop = Properties.create(&host.root, {0, 0, 300, 340}, .List)
    var bases: Array'(*u8)
    bases.add(cast(*u8) &t0)
    bases.add(cast(*u8) &t1)
    prop.addStructMulti(MultiTile, bases.toSlice(), "S")
    prop.edView.sendResizeEvent()

    let tintItem = findFieldItem(prop, "tint")
    @assert(tintItem != null)
    @assert(prop.fieldIsMixed(tintItem))

    // Make them equal and refresh: no longer mixed.
    t1.tint = Pixel.Argb.Red
    prop.refresh()
    @assert(!prop.fieldIsMixed(tintItem))

    host.shutdown()
}

//
// Per-item validation (info / warning / error) state.
//

struct ValData
{
    name:  String
    count: s32 = 5
}

impl Gui.IPropertyNotify for ValData
{
    mtd impl validateItem(_list: *Gui.Properties, item: *Gui.PropertiesItem)->Gui.PropValidationResult
    {
        switch item.typeValue.crc
        {
        case Reflection.fieldCrc(ValData, #nameof(ValData.name)):
            if .name.length == 0 do
                return {.Error, "Name is required."}
        case Reflection.fieldCrc(ValData, #nameof(ValData.count)):
            if .count > 100 do
                return {.Warning, "Count is unusually large."}
        }
        return {}
    }
}

// Validation is computed from the bound struct on build and after each change.
#test
{
    var host: GuiHeadlessHost
    host.setup(300, 240)

    var data: ValData                                      // name empty -> error, count ok
    let prop = Properties.create(&host.root, {0, 0, 280, 220}, .List)
    prop.addStruct(data, "S")
    prop.edView.sendResizeEvent()

    let nameItem  = findFieldItem(prop, "name")
    let countItem = findFieldItem(prop, "count")
    @assert(nameItem != null and countItem != null)

    @assert(nameItem.validation == .Error)                 // empty name flagged on build
    @assert(nameItem.validationMsg == "Name is required.")
    @assert(countItem.validation == .None)

    // Editing into an invalid range raises a warning.
    countItem.editBox.setText("150")
    prop.validateNative(countItem)
    @assert(data.count == 150)
    @assert(countItem.validation == .Warning)
    @assert(countItem.validationMsg == "Count is unusually large.")

    // Fixing the name clears its error.
    nameItem.editBox.setText("hello")
    prop.validateDynamicString(nameItem)
    @assert(nameItem.validation == .None)

    host.shutdown()
}

// A validation set manually (no notify interface) is kept across refreshes.
#test
{
    var host: GuiHeadlessHost
    host.setup(280, 220)

    var data: PropHeadlessData                             // no IPropertyNotify
    let prop = Properties.create(&host.root, {0, 0, 260, 200}, .List)
    prop.addStruct(data)
    prop.edView.sendResizeEvent()

    let it = findFieldItem(prop, "count")
    @assert(it != null)

    prop.setItemValidation(it, .Error, "bad value")
    @assert(it.validation == .Error and it.validationMsg == "bad value")

    // updateValidation must not clobber a manual state when there is no notify interface.
    prop.updateValidation()
    @assert(it.validation == .Error)

    prop.setItemValidation(it, .None)
    @assert(it.validation == .None)

    host.shutdown()
}

// Read-only fields gray (disable) their editor, while staying visible. Covers both the
// ReadOnly attribute and the dynamic isItemReadOnly notify API, including toggling at runtime.
#test
{
    var host: GuiHeadlessHost
    host.setup(260, 360)

    g_PropRoDynamic = true

    var data: PropHeadlessRoData
    let prop = Properties.create(&host.root, {0, 0, 240, 340})
    prop.addStruct(data)

    let normalItem  = findFieldItem(prop, #nameof(PropHeadlessRoData.normal))
    let lockedItem  = findFieldItem(prop, #nameof(PropHeadlessRoData.locked))
    let dynamicItem = findFieldItem(prop, #nameof(PropHeadlessRoData.dynamic))
    @assert(normalItem != null and lockedItem != null and dynamicItem != null)
    @assert(normalItem.editBox != null and lockedItem.editBox != null and dynamicItem.editBox != null)

    // Edit-box editors stay focusable but become read-only. The editable field is not; the
    // read-only fields (attribute + dynamic) are. They are not changeable either.
    @assert(!normalItem.editBox.editBoxFlags.has(.ReadOnly))
    @assert(lockedItem.editBox.editBoxFlags.has(.ReadOnly))
    @assert(dynamicItem.editBox.editBoxFlags.has(.ReadOnly))
    @assert(prop.canChangeItem(normalItem))
    @assert(!prop.canChangeItem(lockedItem))
    @assert(!prop.canChangeItem(dynamicItem))

    // Clearing the dynamic flag releases only that field; the attribute one stays locked.
    g_PropRoDynamic = false
    prop.setCurrentSection(Swag.U32.Max)
    @assert(!dynamicItem.editBox.editBoxFlags.has(.ReadOnly))
    @assert(prop.canChangeItem(dynamicItem))
    @assert(lockedItem.editBox.editBoxFlags.has(.ReadOnly))
    @assert(!prop.canChangeItem(lockedItem))

    host.shutdown()
}

// Reordering array elements (static + dynamic) and removing a dynamic element by the correct
// index, including struct arrays whose element rows are interleaved with their field rows.
#test
{
    var host: GuiHeadlessHost
    host.setup(300, 520)

    var data: PropMoveData
    data.dyn.resize(3)
    data.dyn[0].id = 10
    data.dyn[1].id = 20
    data.dyn[2].id = 30
    data.stat[0]   = 1
    data.stat[1]   = 2
    data.stat[2]   = 3

    let prop = Properties.create(&host.root, {0, 0, 280, 500}, .List)
    prop.addStruct(data)

    let dynArr = findFieldItem(prop, #nameof(PropMoveData.dyn))
    @assert(dynArr != null)
    var elems: Array'(*PropertiesItem)
    foreach it in prop.items where it.parent == dynArr do
        elems.add(it)
    @assert(elems.count == 3)

    // Move element 0 down -> [20,10,30], then element 2 up -> [20,30,10].
    prop.moveArrayValue(elems[0], 1)
    @assert(data.dyn[0].id == 20 and data.dyn[1].id == 10 and data.dyn[2].id == 30)
    prop.moveArrayValue(elems[2], -1)
    @assert(data.dyn[0].id == 20 and data.dyn[1].id == 30 and data.dyn[2].id == 10)

    // Move at the boundaries is a no-op.
    prop.moveArrayValue(elems[0], -1)
    @assert(data.dyn[0].id == 20)

    // Remove the element at index 1 (id 30) -> [20,10]. Used to compute an out-of-bounds index
    // for struct arrays with more than one element.
    prop.removeArrayValue(elems[1])
    @assert(data.dyn.count == 2 and data.dyn[0].id == 20 and data.dyn[1].id == 10)

    // Static array reorder: [1,2,3], move index 0 down -> [2,1,3].
    let statArr = findFieldItem(prop, #nameof(PropMoveData.stat))
    @assert(statArr != null)
    var statElems: Array'(*PropertiesItem)
    foreach it in prop.items where it.parent == statArr do
        statElems.add(it)
    @assert(statElems.count == 3)
    prop.moveArrayValue(statElems[0], 1)
    @assert(data.stat[0] == 2 and data.stat[1] == 1 and data.stat[2] == 3)

    host.shutdown()
}

// The context-menu commands run through the shared gui action system (ActionProperties /
// IActionUI): update() computes each item's enabled state, execute() performs the change via a
// real CommandEvent — no hardcoded result-string switch.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 520)

    var data: PropMoveData
    data.dyn.resize(3)
    data.dyn[0].id = 10
    data.dyn[1].id = 20
    data.dyn[2].id = 30

    let prop = Properties.create(&host.root, {0, 0, 280, 500}, .List)
    prop.addStruct(data)

    // Copy the first element's 'id' field (value 10) and read it back from the clipboard.
    let idField = findFieldItem(prop, #nameof(PropMoveElem.id))
    @assert(idField != null)
    prop.menuItem = idField
    prop.sendCommandEvent(ActionProperties.Copy)
    var got: s32
    @assert(Clipboard.getTypedValue(&got, idField.type) and got == 10)

    let dynArr = findFieldItem(prop, #nameof(PropMoveData.dyn))
    var elems: Array'(*PropertiesItem)
    foreach it in prop.items where it.parent == dynArr do
        elems.add(it)
    @assert(elems.count == 3)

    // update(): Move Up is disabled on the first element, enabled on the second.
    prop.menuItem = elems[0]
    var st = prop.sendComputeCommandStateEvent(ActionProperties.MoveUp)
    @assert(st.setFlags.has(.Disabled) and st.disabled)
    prop.menuItem = elems[1]
    st = prop.sendComputeCommandStateEvent(ActionProperties.MoveUp)
    @assert(st.setFlags.has(.Disabled) and !st.disabled)

    // execute(): Move Up on element 1 reorders the underlying array, dispatched through the real
    // CommandEvent path (sendCommandEvent updates state first, then sends the command).
    prop.sendCommandEvent(ActionProperties.MoveUp)
    @assert(data.dyn[0].id == 20 and data.dyn[1].id == 10 and data.dyn[2].id == 30)

    host.shutdown()
}

// --- Custom editor registry -------------------------------------------------

struct PropHeadlessAngle
{
    deg: s32 = 45
}

struct PropHeadlessAngleData
{
    rot:  PropHeadlessAngle
    name: string = "x"
}

var g_PropAngleEditorCalls: s32

// A custom editor for PropHeadlessAngle: a single editbox showing "<deg> deg" instead of
// expanding the struct into its 'deg' sub-field. Implemented as an IPropertyEditor and
// registered globally at #init (below) — the non-intrusive, interface-based registry path
// (the type itself stays untouched).
struct PropAngleEditor {}

impl IPropertyEditor for PropAngleEditor
{
    mtd impl canEdit(type: typeinfo)->bool
    {
        return type == PropHeadlessAngle
    }

    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: [*] u8, parent: *PropertiesItem)->*PropertiesItem
    {
        g_PropAngleEditorCalls += 1

        let item  = list.addItem(value, data, parent)
        let angle = cast(*PropHeadlessAngle) data

        with let ed = EditBox.create(item.line, "", {0, 0, 120, 24})
        {
            // No numeric input mask: the editor shows a "<deg> deg" suffixed string, so the
            // writer parses the leading number out of the free text.
            .sigLoseFocus += func|list, item, angle|(ed)
            {
                angle.deg = cast(s32) (catch StrConv.toNum's64(ed.getText()))
                list.hasChanged(item)
            }
        }

        item.editBox = ed
        item.sigRefresh += func|angle|(item)
        {
            item.editBox.setText(Format.toString("% deg", angle.deg))
        }

        return item
    }
}

#init
{
    Properties.registerEditor'(PropAngleEditor)()
}

// A registered IPropertyEditor that claims a type overrides the built-in dispatch: the struct
// is not expanded into its sub-fields, the editor's construct runs once per field of that type,
// and its item.sigRefresh drives the displayed value.
#test
{
    var host: GuiHeadlessHost
    host.setup(260, 320)

    var data: PropHeadlessAngleData

    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    g_PropAngleEditorCalls = 0
    prop.addStruct(data)

    // The editor ran once for 'rot'; the struct was NOT expanded into a 'deg' child row, so
    // items = [section, rot, name].
    @assert(g_PropAngleEditorCalls == 1)
    @assert(prop.items.count == 3)

    let rot = findFieldItem(prop, #nameof(PropHeadlessAngleData.rot))
    @assert(rot != null)
    @assert(rot.editBox != null)
    @assert(rot.numChilds == 0)
    @assert(rot.editBox.getText() == "45 deg")

    // A plain field next to it still uses the built-in editor.
    let name = findFieldItem(prop, #nameof(PropHeadlessAngleData.name))
    @assert(name != null and name.editBox != null)

    // The registry resolves the editor for the angle type, but not for an unrelated one.
    @assert(Properties.findEditor(PropHeadlessAngle) != null)
    @assert(Properties.findEditor(string) == null)

    host.shutdown()
}

// --- Reset to default -------------------------------------------------------

struct PropDefaultData
{
    count:   s32 = 42
    name:    string = "hello"          // static string: read-only, never resettable
    enabled: bool = true
}

var g_PropDefResetCalls: s32
var g_PropDefForceModified: bool

struct PropDefaultCustom
{
    val: s32 = 5
}

impl IPropertyNotify for PropDefaultCustom
{
    // Force the modified state regardless of the actual value (the customizable test).
    mtd impl isItemAtDefault(_list: *Properties, item: *PropertiesItem)->PropDefaultState
    {
        if item.typeValue.name == #nameof(PropDefaultCustom.val) do
            return g_PropDefForceModified ? .Modified : .AtDefault
        return .Auto
    }

    // Take over the reset itself.
    mtd impl resetItemToDefault(_list: *Properties, item: *PropertiesItem)->bool
    {
        if item.typeValue.name == #nameof(PropDefaultCustom.val)
        {
            g_PropDefResetCalls += 1
            return true
        }
        return false
    }
}

// Built-in detection: a field equal to its declared default is not modified; editing it flags the
// row (isModified + a visible revert button) and Properties.resetItemDefault restores the value.
#test
{
    var host: GuiHeadlessHost
    host.setup(260, 320)

    var data: PropDefaultData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    let countItem = findFieldItem(prop, #nameof(PropDefaultData.count))
    @assert(countItem != null)

    // The default value comes from a real default-constructed instance of the struct.
    @assert(countItem.defaultData != null)
    @assert(dref cast(*s32) countItem.defaultData == 42)

    // Freshly built: at default -> not modified, no revert button, cannot... still resettable type.
    @assert(!countItem.isModified)
    @assert(prop.canReset(countItem))
    @assert(countItem.revertButton == null or !countItem.revertButton.isVisible())

    // Static string field is read-only -> never resettable and never modified.
    let nameItem = findFieldItem(prop, #nameof(PropDefaultData.name))
    @assert(nameItem != null)
    @assert(!prop.canReset(nameItem))
    @assert(!nameItem.isModified)

    // Edit the value away from its default: the row becomes modified and shows the revert arrow.
    countItem.editBox.setText("99")
    prop.validateNative(countItem)
    @assert(data.count == 99)
    @assert(countItem.isModified)
    @assert(countItem.revertButton != null and countItem.revertButton.isVisible())

    // Reset restores the declared default and clears the modified state / hides the arrow.
    prop.resetItemDefault(countItem)
    @assert(data.count == 42)
    @assert(!countItem.isModified)
    @assert(!countItem.revertButton.isVisible())

    host.shutdown()
}

// The "Reset to default" context-menu command goes through the shared action system: update()
// disables it while the value is at its default and enables it once modified; execute() resets.
#test
{
    var host: GuiHeadlessHost
    host.setup(260, 320)

    var data: PropDefaultData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    let countItem = findFieldItem(prop, #nameof(PropDefaultData.count))
    prop.menuItem = countItem

    // At default: the command exists but is disabled.
    var st = prop.sendComputeCommandStateEvent(ActionProperties.ResetDefault)
    @assert(st.setFlags.has(.Disabled) and st.disabled)

    // After a change: enabled, and executing it restores the default.
    data.count = 7
    prop.updateStates()
    @assert(countItem.isModified)
    st = prop.sendComputeCommandStateEvent(ActionProperties.ResetDefault)
    @assert(st.setFlags.has(.Disabled) and !st.disabled)

    prop.sendCommandEvent(ActionProperties.ResetDefault)
    @assert(data.count == 42 and !countItem.isModified)

    host.shutdown()
}

// The test and the reset are both customizable through IPropertyNotify: isItemAtDefault forces the
// modified state (even though the value equals the default), and resetItemToDefault handles reset.
#test
{
    var host: GuiHeadlessHost
    host.setup(260, 320)

    g_PropDefResetCalls   = 0
    g_PropDefForceModified = true

    var data: PropDefaultCustom
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    let valItem = findFieldItem(prop, #nameof(PropDefaultCustom.val))
    @assert(valItem != null)

    // Value equals the declared default (5), but the override forces "modified".
    @assert(dref cast(*s32) valItem.data == 5)
    @assert(valItem.isModified)

    // Reset is taken over by the notify interface: our handler runs, the built-in copy does not.
    prop.resetItemDefault(valItem)
    @assert(g_PropDefResetCalls == 1)

    // Flipping the override back reports "at default".
    g_PropDefForceModified = false
    prop.updateStates()
    @assert(!valItem.isModified)

    host.shutdown()
}

// Grid mode: the revert column is reserved on the right of every resettable row (docked, present
// even while at default), so the value editor keeps a constant width; toggling the arrow on/off
// never resizes it. Mirrors the Godot/Unreal revert column.
#test
{
    var host: GuiHeadlessHost
    host.setup(360, 320)

    var data: PropDefaultData
    let prop = Properties.create(&host.root, {0, 0, 340, 300}, .Grid)
    prop.addStruct(data)

    let countItem = findFieldItem(prop, #nameof(PropDefaultData.count))
    @assert(countItem != null and countItem.editBox != null)

    // The revert arrow is docked to the right of the row (the trailing action margin) and present
    // from the start; while at its default the arrow is hidden (disabled) but the column stays
    // reserved so the editor keeps a constant width.
    let btn = countItem.revertButton
    @assert(btn != null and btn.dockStyle == .Right)
    @assert(btn.isDisabled())
    let editWidthClean = countItem.editBox.position.width

    // Change the value: the arrow becomes active WITHOUT resizing the editor.
    data.count = 5
    prop.updateStates()
    @assert(countItem.isModified and !btn.isDisabled())
    @assert(countItem.editBox.position.width == editWidthClean)

    // Reset hides the arrow again; the editor width is still unchanged.
    prop.resetItemDefault(countItem)
    @assert(!countItem.isModified and btn.isDisabled())
    @assert(countItem.editBox.position.width == editWidthClean)

    host.shutdown()
}

// Multi-selection: a field is "modified" when it differs from the default in ANY edited instance,
// and reset writes the declared default into every instance.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 360)

    var t0, t1: PropDefaultData
    t0.count = 42                                          // at default
    t1.count = 7                                           // differs

    let prop = Properties.create(&host.root, {0, 0, 300, 340}, .List)
    var bases: Array'(*u8)
    bases.add(cast(*u8) &t0)
    bases.add(cast(*u8) &t1)
    prop.addStructMulti(PropDefaultData, bases.toSlice(), "S")

    let countItem = findFieldItem(prop, #nameof(PropDefaultData.count))
    @assert(countItem != null)
    @assert(countItem.isModified)                         // one instance differs

    prop.resetItemDefault(countItem)
    @assert(t0.count == 42 and t1.count == 42)
    @assert(!countItem.isModified)

    host.shutdown()
}
