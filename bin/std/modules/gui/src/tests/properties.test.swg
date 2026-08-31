#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

struct PropHeadlessData
{
    count:   s32          = 42
    label:   #null string = "hello"
    enabled: bool         = true
}

struct PropHeadlessHiddenData
{
    visible: s32 = 1

    #[Properties.Hidden]
    persistedOnly: s32 = 2
}

struct PropHeadlessCustomData
{
    origin: Math.Point = {10, 20}
    count:  s32        = 3
}

enum PropHeadlessChoice
{
    Low
    Mid
    High
}

struct PropHeadlessEnumData
{
    choice: PropHeadlessChoice = .Mid
}

// Carries one of each presentation attribute a text resolver has to reach.
struct PropHeadlessResolvedData
{
    #[Category("Numbers"), Name("Count")]
    count: s32 = 42

    #[Name("Line"), BoolCombo("Straight", "Bezier")]
    bezier: bool
}

struct PropHeadlessSliderData
{
    #[SliderMinMax(0, 100)]
    volume: s32 = 50

    #[SliderMinMax(0, 10)]
    level: s32 = 5
}

struct PropHeadlessGroupedData
{
    #[Category("Numbers")]
    count: s32 = 42

    label: #null string = "hello"

    #[Category("Flags")]
    enabled: bool = true
}

struct PropHeadlessRoData
{
    normal: s32 = 1

    #[ReadOnly]
    locked: s32 = 2

    dynamic: s32 = 3
}

struct PropMoveElem
{
    id: s32 = 0
}

struct PropMoveData
{
    dyn:  Array'PropMoveElem
    stat: [3] s32
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
    var host: Testing.HeadlessHost
    host.setup(260, 320)
    defer host.shutdown()
    var data: PropHeadlessData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    // 1 implicit section item + 3 fields.
    Swag.assert(prop.items.count == 4)
    Swag.assert(prop.items[0]!.flags.has(.Section))
}

// Public configuration methods keep their observable state synchronized, and clear makes the
// control reusable without retaining rows or selection state.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 320)
    defer host.shutdown()
    var data: PropHeadlessData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.setEditorWidth(280)
    prop.setUsingFieldsLast(true)
    prop.setRevertButtonsVisible(false)
    prop.addStruct(data)

    Swag.assert(prop.editorWidth == 280)
    Swag.assert(prop.usingFieldsLast)
    Swag.assert(!prop.revertButtonsVisible)
    Swag.assert(prop.items.count == 4)

    prop.focusNavigation()
    Swag.assert(prop.selItem != null)
    prop.setFilter("no matching property")
    Swag.assert(!prop.items[1]!.line.isVisible())

    prop.clear()
    Swag.assert(prop.items.count == 0)
    Swag.assert(!prop.selItem)
}

// A field kept for persistence can opt out of a generated editor without leaving its structure.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 180)
    defer host.shutdown()
    var data: PropHeadlessHiddenData
    let prop = Properties.create(&host.root, {0, 0, 240, 160})
    prop.addStruct(data)

    Swag.assert(prop.items.count == 2)
    Swag.assert(prop.items[1]!.typeValue.name == #nameof(PropHeadlessHiddenData.visible))
    Swag.assert(data.persistedOnly == 2)
}

// PropertiesCtrl keeps visible grid rows after the same staged layout sequence
// used by the gui4 example: create at a placeholder height, add structs, then
// dock into its final parent.
#test
{
    var host: Testing.HeadlessHost
    host.setup(1240, 820)
    defer host.shutdown()
    let page = Wnd.create'Wnd(&host.root, {24, 104, 1192, 666})

    var data: PropHeadlessGroupedData
    let ctrl = PropertiesCtrl.create(page, {0, 0, 560, 10}, .Grid, .SectionTabs | .SectionNavigation | .SearchBar)
    ctrl.dockStyle = .Left
    ctrl.margin.z  = 24
    ctrl.properties.setEditorWidth(300)
    ctrl.properties.setNameColumnWidth(150)
    ctrl.addStruct(data, "Settings")
    ctrl.splitter.setPaneSize(0, 160)
    let paneIt = ctrl.splitter.items[0]!
    paneIt.preserveSize = true

    let preview = Wnd.create'FrameWnd(page, {})
    preview.dockStyle = .Center

    page.applyLayout()

    Swag.assert(ctrl.position == Math.Rectangle{0, 0, 560, 666})
    Swag.assert(ctrl.splitter.position.width > 0)
    Swag.assert(ctrl.splitter.position.height > 0)
    Swag.assert(ctrl.properties.position.width > 0)
    Swag.assert(ctrl.properties.position.height > 0)
    Swag.assert(ctrl.properties.edView.position.width > 0)
    Swag.assert(ctrl.properties.edView.position.height > 0)
    Swag.assert(ctrl.properties.items.count == 6)
    Swag.assert(ctrl.properties.items[0]!.line.isVisible())
    Swag.assert(ctrl.properties.items[1]!.line.isVisible())
    Swag.assert(ctrl.properties.items[1]!.line.position.height == ctrl.properties.gridLineHeight)
    Swag.assert(ctrl.properties.items[1]!.line.position.y >= ctrl.properties.gridLineHeight)
}

// Keyboard navigation: focusNavigation selects the first navigable row, arrows move the
// highlight over the editable rows (clamped), Home/End jump to the ends.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 320)
    defer host.shutdown()
    var data: PropHeadlessData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)     // [0]=section [1]=count [2]=label [3]=enabled

    prop.focusNavigation()
    Swag.assert(prop.selItem == prop.items[1])     // section row is skipped
    Swag.assert(host.app.keyboardFocusWnd == cast(#null *Wnd) prop.edView)

    host.keyPress(Input.Key.Down)
    Swag.assert(prop.selItem == prop.items[2])
    host.keyPress(Input.Key.Down)
    Swag.assert(prop.selItem == prop.items[3])
    host.keyPress(Input.Key.Down)     // clamp at the last row
    Swag.assert(prop.selItem == prop.items[3])
    host.keyPress(Input.Key.Up)
    Swag.assert(prop.selItem == prop.items[2])

    host.keyPress(Input.Key.Home)
    Swag.assert(prop.selItem == prop.items[1])
    host.keyPress(Input.Key.End)
    Swag.assert(prop.selItem == prop.items[3])
}

// Enter starts editing the selected row (focuses its editor); Escape returns to
// navigation mode (focus back on the grid).
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 320)
    defer host.shutdown()
    var data: PropHeadlessData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    prop.focusNavigation()     // selItem = count row
    host.keyPress(Input.Key.Return)
    Swag.assert(host.app.keyboardFocusWnd == cast(#null *Wnd) prop.items[1]!.editBox)

    host.keyPress(Input.Key.Escape)
    Swag.assert(host.app.keyboardFocusWnd == cast(#null *Wnd) prop.edView)
}

// While editing, Up/Down auto-commit and move the selection back to navigation
// mode on the adjacent row.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 320)
    defer host.shutdown()
    var data: PropHeadlessData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    prop.focusNavigation()              // count row
    host.keyPress(Input.Key.Return)     // edit count
    Swag.assert(host.app.keyboardFocusWnd == cast(#null *Wnd) prop.items[1]!.editBox)

    host.keyPress(Input.Key.Down)     // commit + move to label row
    Swag.assert(prop.selItem == prop.items[2])
    Swag.assert(host.app.keyboardFocusWnd == cast(#null *Wnd) prop.edView)
}

// Tab commits the current edit and starts editing the next editable row.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 320)
    defer host.shutdown()
    var data: PropHeadlessData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    prop.focusNavigation()
    host.keyPress(Input.Key.Return)     // edit count
    host.keyPress(Input.Key.Tab)        // -> edit label row
    Swag.assert(prop.selItem == prop.items[2])
    Swag.assert(host.app.keyboardFocusWnd == cast(#null *Wnd) prop.items[2]!.editBox)
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
    var host: Testing.HeadlessHost
    host.setup(400, 600)
    defer host.shutdown()
    var data: PropHeadlessArrayData
    data.actions.resize(1)
    let prop = Properties.create(&host.root, {0, 0, 380, 560}, .List)
    prop.addStruct(data, "S")
    prop.edView.sendResizeEvent()

    // items: [0]=section [1]=origin (vector) [2]=actions (array) [3]=element "0" [4]=visible (bool)
    Swag.assert(Swag.isSet(prop.items[1]!.label) and Swag.isSet(prop.items[2]!.label) and Swag.isSet(prop.items[4]!.label))

    // For each value row, the inner value line must start at or below the label bottom.
    func assertBelowLabel(item: *PropertiesItem)
    {
        let labelBottom = item.label.position.bottom()
        for c in item.line.children
        {
            if c == cast(#null *Wnd) item.label do
                continue
            Swag.assert(c.position.y >= labelBottom)
        }
    }

    assertBelowLabel(prop.items[1]!)     // vector
    assertBelowLabel(prop.items[2]!)     // array count editor
    assertBelowLabel(prop.items[4]!)     // bool

    // Rows and labels span the whole control (the value editors keep their own cap)
    let originItem = prop.items[1]!
    let rowWidth   = originItem.line.position.width
    Swag.assert(rowWidth > cast(f32) prop.editorWidth)
    Swag.assert(Math.isEqualEpsilon(originItem.label.position.x, cast(f32) prop.leftMargin, 0.01))
    Swag.assert(Math.isEqualEpsilon(originItem.label.position.width, rowWidth - prop.leftMargin - prop.rightMargin, 0.01))

    let actionsItem = prop.items[2]!
    let actionRight = cast(f32) prop.editorWidth - prop.rightMargin - PropRevertGap
    Swag.assert(Swag.isSet(actionsItem.arrayAddButton))
    Swag.assert(Math.isEqualEpsilon(actionsItem.label.position.x + actionsItem.arrayAddButton.position.right(), actionRight, 0.01))

    // The bool description is nudged down to optically center on the box: it carries a
    // positive top text padding derived from the font descent (never a hard-coded value).
    let chk    = prop.items[4]!.checkBox
    let chkRow = chk.parent!
    var desc: #null *Label
    for c in chkRow.children do
        if c != cast(#null *Wnd) chk do
            desc = cast(*Label) c
    let descLbl = desc!
    Swag.assert(descLbl.textPadding.y > 0)
    Swag.assert(Math.abs(descLbl.textPadding.y + descLbl.textPadding.w) < 0.01)     // pure translation, no height loss
    Swag.assert(chkRow.position.height >= descLbl.position.bottom())                // wrapped info text is not clipped
}

struct PropHeadlessColorData
{
    f0, f1, f2, f3, f4, f5, f6, f7: s32
    tint: Pixel.Color
    f8, f9, f10, f11, f12, f13:     s32
}

// While an editor popup (e.g. the color picker) is open the grid is modal: mouse wheel
// events over the list are swallowed so it cannot scroll out from under the anchored
// popup. Clearing the popup restores scrolling.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 200)
    defer host.shutdown()
    var data: PropHeadlessColorData
    let prop = Properties.create(&host.root, {0, 0, 280, 180}, .List)
    prop.addStruct(data, "S")
    prop.edView.sendResizeEvent()

    Swag.assert(prop.scrollWnd.scrollSize.y > prop.position.height)     // content overflows -> scrollable

    func sendWheel(p: *Properties, deltaY: f32)
    {
        var wheel = MouseEvent{kind: .Wheel}
        wheel.delta.y    = deltaY
        wheel.surfacePos = {20, 90}
        p.edView.sendEvent(&wheel)
    }

    // Control: with no popup, the wheel scrolls the list.
    let y0 = prop.scrollWnd.scrollPosition().y
    sendWheel(prop, -6)     // scroll down
    let y1 = prop.scrollWnd.scrollPosition().y
    Swag.assert(y1 != y0)

    // Modal: with a popup open, the same wheel is swallowed and the list stays put.
    let popup = Wnd.create'Wnd(&host.root, {})
    prop.editPopup = popup
    sendWheel(prop, -6)
    Swag.assert(prop.scrollWnd.scrollPosition().y == y1)

    // Clearing the popup restores scrolling.
    prop.editPopup = null
    sendWheel(prop, 6)     // scroll back up
    Swag.assert(prop.scrollWnd.scrollPosition().y != y1)
}

func findIconButton(w: *Wnd)->#null *IconButton
{
    for c in w.children
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
    var host: Testing.HeadlessHost
    host.setup(300, 200)
    defer host.shutdown()
    var data: PropHeadlessColorData
    let prop = Properties.create(&host.root, {0, 0, 280, 180}, .List)
    prop.addStruct(data, "S")
    prop.edView.sendResizeEvent()

    let btn = findIconButton(prop.items[9]!.line)!     // the color swatch button

    // Hover the button (no popup yet) -> hot.
    host.sendMouseEvent(btn, .Enter, {0, 0}, .Left, .None)
    Swag.assert(btn.isHot)

    // With a popup open, a MouseLeave must still reach the button and clear the hover.
    let popup = Wnd.create'Wnd(&host.root, {})
    prop.editPopup = popup
    host.sendMouseEvent(btn, .Leave, {0, 0}, .Left, .None)
    Swag.assert(!btn.isHot)
}

// In navigation mode, Space toggles a bool row's checkbox in place.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 320)
    defer host.shutdown()
    var data: PropHeadlessData     // enabled = true
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    prop.focusNavigation()
    host.keyPress(Input.Key.End)     // enabled (checkbox) row
    let chk = prop.items[3]!.checkBox
    Swag.assert(chk.isChecked())

    host.keyPress(Input.Key.Space)
    Swag.assert(!chk.isChecked())
    host.keyPress(Input.Key.Space)
    Swag.assert(chk.isChecked())
}

// Navigating a slider row: Right steps the slider track and focuses it (auto-commit
// model), a further Right keeps stepping, Down commits and moves to the next row.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    defer host.shutdown()
    var data: PropHeadlessSliderData     // volume=50, level=5
    let prop = Properties.create(&host.root, {0, 0, 300, 200})
    prop.addStruct(data, "S")     // [0]=section [1]=volume [2]=level
    prop.edView.sendResizeEvent()

    prop.focusNavigation()
    Swag.assert(prop.selItem == prop.items[1])     // section is not navigable in list mode

    // The very first Right in navigation steps the slider and focuses it (so the
    // value changes immediately, not only on the second press).
    host.keyPress(Input.Key.Right)
    let volumeSlider = prop.items[1]!.sliderBox
    Swag.assert(volumeSlider.value() > 50)
    Swag.assert(data.volume > 50)
    Swag.assert(host.app.keyboardFocusWnd == cast(#null *Wnd) volumeSlider.slider)

    // A further Right keeps stepping (now in edit mode on the focused slider).
    let v1 = volumeSlider.value()
    host.keyPress(Input.Key.Right)
    Swag.assert(volumeSlider.value() > v1)

    // Down auto-commits and moves to the next row, back in navigation mode.
    host.keyPress(Input.Key.Down)
    Swag.assert(prop.selItem == prop.items[2])
    Swag.assert(host.app.keyboardFocusWnd == cast(#null *Wnd) prop.edView)
}

// Enter on a slider row edits its value box like a plain editbox row: it focuses the
// inner EditBox and selects its text so the value can be typed over right away.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 220)
    defer host.shutdown()
    var data: PropHeadlessSliderData     // volume=50, level=5
    let prop = Properties.create(&host.root, {0, 0, 300, 200})
    prop.addStruct(data, "S")     // [0]=section [1]=volume [2]=level
    prop.edView.sendResizeEvent()

    prop.focusNavigation()
    Swag.assert(prop.selItem == prop.items[1])

    let edit = prop.items[1]!.sliderBox.edit

    // Enter focuses the value box (not the slider track) and selects its whole text.
    host.keyPress(Input.Key.Return)
    Swag.assert(host.app.keyboardFocusWnd == cast(#null *Wnd) edit)
    Swag.assert(edit.selBeg == 0 and edit.selEnd == (edit.text()).count)
    Swag.assert((edit.text()).count > 0)
}

// Editing an enum row: Enter focuses the combo, Left/Right change the selection
// (reaching the combo, not intercepted) and write back to the data.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 200)
    defer host.shutdown()
    var data: PropHeadlessEnumData     // choice = Mid (index 1)
    let prop = Properties.create(&host.root, {0, 0, 280, 180})
    prop.addStruct(data, "E")     // [0]=section [1]=choice
    prop.edView.sendResizeEvent()

    prop.focusNavigation()
    Swag.assert(prop.selItem == prop.items[1])
    let combo = prop.items[1]!.comboBox
    Swag.assert(combo.selectedIndex == 1)     // Mid

    // Enter opens the drop-down popup. The grid keeps the keyboard focus and forwards
    // the keys to the popup (so they never leak to page navigation outside the grid).
    host.keyPress(Input.Key.Return)
    Swag.assert(combo.popup != null)
    Swag.assert(host.app.keyboardFocusWnd == cast(#null *Wnd) prop.edView)

    let pview = cast(*PopupListView) combo.popup!.scrollWnd.view!
    Swag.assert(pview.hotIdx == 1)     // highlight starts on the current value

    // Down moves the highlight only; the committed value stays until Enter.
    host.keyPress(Input.Key.Down)     // highlight Mid -> High
    Swag.assert(pview.hotIdx == 2)
    Swag.assert(combo.selectedIndex == 1)     // not committed yet
    Swag.assert(data.choice == .Mid)

    // A per-frame mouse-move outside the popup must not wipe the keyboard highlight.
    host.sendMouseEvent(cast(*Wnd) pview!, MouseEvent.Kind.Move, {2, 2}, Input.MouseButton.Left, Input.KeyModifiers.None)
    Swag.assert(pview.hotIdx == 2)

    // Enter commits the highlighted item (writes the data) and closes the edit.
    host.keyPress(Input.Key.Return)
    host.pump()
    Swag.assert(combo.selectedIndex == 2)
    Swag.assert(data.choice == .High)
    Swag.assert(combo.popup == null)
    Swag.assert(host.app.keyboardFocusWnd == cast(#null *Wnd) prop.edView)
}

// A row with a custom/composite editor (e.g. a Math.Point) is navigable and can be
// activated: Enter focuses the first inner editor, Down auto-commits to the next row.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    var data: PropHeadlessCustomData
    let prop = Properties.create(&host.root, {0, 0, 300, 180})
    prop.addStruct(data, "C")     // [0]=section [1]=origin [2]=count
    prop.edView.sendResizeEvent()

    prop.focusNavigation()
    Swag.assert(prop.selItem == prop.items[1])     // the custom 'origin' row is selectable

    host.keyPress(Input.Key.Return)     // edit -> focus the first inner editbox
    let f = host.app.keyboardFocusWnd!
    Swag.assert(f.type == EditBox)

    host.keyPress(Input.Key.Down)     // commit + move to the next row
    Swag.assert(prop.selItem == prop.items[2])
    Swag.assert(host.app.keyboardFocusWnd == cast(#null *Wnd) prop.edView)
}

// focusNavigation keeps the already-selected row (so clicking a header/custom row does not
// jump the selection to the first item).
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    var data: PropHeadlessCustomData
    let prop = Properties.create(&host.root, {0, 0, 300, 180})
    prop.addStruct(data, "C")

    prop.setSelItem(prop.items[1])     // as if 'origin' was just clicked
    prop.focusNavigation()
    Swag.assert(prop.selItem == prop.items[1])     // kept, not reset to the first row
}

// A named section becomes the first item and is registered.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 320)
    defer host.shutdown()
    var data: PropHeadlessData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data, "Settings")

    Swag.assert(prop.items.count == 4)
    Swag.assert(prop.items[0]!.flags.has(.Section))
    Swag.assert(prop.sections.count == 1)
}

// PropertiesCtrl grid keeps deterministic line and editor heights.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 180)
    defer host.shutdown()
    var data: PropHeadlessData
    let ctrl = PropertiesCtrl.create(&host.root, {0, 0, 320, 120}, .Grid, .None)
    ctrl.addStruct(data, "Settings")
    ctrl.properties.edView.sendResizeEvent()

    Swag.assert(ctrl.properties.items.count == 4)
    let it0 = ctrl.properties.items[0]!
    let it1 = ctrl.properties.items[1]!
    let it2 = ctrl.properties.items[2]!
    let it3 = ctrl.properties.items[3]!
    Swag.assert(it0.line.position.y == 2)
    Swag.assert(it1.line.position.y == 38)
    Swag.assert(it2.line.position.y == 74)
    Swag.assert(it3.line.position.y == 110)
    Swag.assert(it0.line.position.height == 32)
    Swag.assert(it1.line.position.height == 32)
    Swag.assert(it2.line.position.height == 32)
    Swag.assert(it3.line.position.height == 32)
    Swag.assert(it0.line.position.width > 0)

    let countItem = it1
    Swag.assert(countItem.label.position == Math.Rectangle{0, 0, 150, 32})
    Swag.assert(countItem.editBox.position.height == ctrl.properties.themeMetrics().editBox_Height)
    Swag.assert(countItem.editBox.position.y == Math.round((countItem.line.position.height - countItem.editBox.position.height) * 0.5))
    Swag.assert(ctrl.properties.scrollWnd.scrollSize.y > ctrl.properties.position.height)
}

// Properties list keeps rows visible after being docked with a filter bar, as
// used by the second page of gui4.
#test
{
    var host: Testing.HeadlessHost
    host.setup(1240, 820)
    defer host.shutdown()
    let page = Wnd.create'Wnd(&host.root, {24, 104, 1192, 666})

    let filter = EditBox.create(page, "")
    filter.dockStyle = .Top
    filter.margin    = {16, 16, 16, 4}

    var dataA: PropHeadlessGroupedData
    var dataB: PropHeadlessGroupedData
    var dataC: PropHeadlessGroupedData
    let prop = Properties.create(page, {}, .List)
    prop.dockStyle = .Center
    prop.margin    = {16, 8, 16, 16}
    prop.addStruct(dataA, "Appearance")
    prop.addStruct(dataB, "Content")
    prop.addStruct(dataC, "Layout")

    page.applyLayout()

    Swag.assert(prop.items.count == 18)
    let it0 = prop.items[0]!
    let it1 = prop.items[1]!
    Swag.assert(it0.line.isVisible())
    Swag.assert(it1.line.isVisible())
    Swag.assert(it0.line.position.height > 0)
    Swag.assert(it1.line.position.y > it0.line.position.y)
    Swag.assert(it0.label.position.height > 0)
    Swag.assert(it1.label.position.height > 0)
    Swag.assert(prop.scrollWnd.scrollSize.y > prop.position.height)
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
    #[Description("Adds a star marker.")]
    Star

    #[Description("Locks the tile.")]
    Lock

    #[Description("Pins the tile.")]
    Pin
}

struct MultiTile
{
    count:  s32         = 0
    flag:   bool        = false
    name:   String
    choice: MultiChoice = .Low
    badges: MultiBadges
    tint:   Pixel.Color
    pos:    Math.Point  = {0, 0}
}

func findFieldItem(prop: *Properties, name: string)->#null *PropertiesItem
{
    for it in prop.items
    {
        let item = it!
        if item.typeValue.name == name do
            return item
    }

    return null
}

// Condensed enum-flag rows keep the marker and its wording in two adjacent cells. The checkbox
// must not take the Center dock used by full-cell editors, which would overlap the label.
#test
{
    var host: Testing.HeadlessHost
    host.setup(520, 420)
    defer host.shutdown()

    var data: MultiTile
    let prop = Properties.create(&host.root, {0, 0, 500, 400}, .Condensed)
    prop.addStruct(data, "Tile")

    host.root.applyLayout()
    host.pump()

    let option      = findFieldItem(prop, #nameof(MultiBadges.Star))!
    let optionLabel = cast(*Label) option.line.children[1]
    Swag.assert(option.checkBox.dockStyle == .Left)
    Swag.assert(option.line.position.height == prop.gridLineHeight)
    Swag.assert(optionLabel.position.x - option.checkBox.position.right() >= PropCondensedCheckTextGap)
    Swag.assert(option.checkBox.position.vertCenter() == optionLabel.position.vertCenter())
}

// Edits applied through the grid write into every selected instance.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 360)
    defer host.shutdown()
    var t0, t1, t2: MultiTile
    let prop = Properties.create(&host.root, {0, 0, 300, 340}, .List)

    var bases: Array'(*u8)
    bases.add(cast(*u8) &t0)
    bases.add(cast(*u8) &t1)
    bases.add(cast(*u8) &t2)
    prop.addStructMulti(MultiTile, bases.toSlice(), "S")
    prop.edView.sendResizeEvent()

    let countItem = findFieldItem(prop, "count")!
    Swag.assert(prop.instanceCount(countItem) == 3)
    Swag.assert(!prop.fieldIsMixed(countItem))     // all start equal (0)

    // Edit the native field: all three instances change together.
    countItem.editBox.setText("9")
    prop.validateNative(countItem)
    Swag.assert(t0.count == 9 and t1.count == 9 and t2.count == 9)

    // Bool toggle propagates to all.
    let flagItem = findFieldItem(prop, "flag")!
    flagItem.checkBox.toggle()
    Swag.assert(t0.flag and t1.flag and t2.flag)

    // Enum selection propagates to all.
    let choiceItem = findFieldItem(prop, "choice")!
    choiceItem.comboBox.setSelectedIndex(2)     // High
    Swag.assert(t0.choice == .High and t1.choice == .High and t2.choice == .High)
}

// A field that differs across instances is "mixed": the editor shows no concrete value,
// and editing it resolves the field on every instance.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 360)
    defer host.shutdown()
    var t0, t1: MultiTile
    t0.count = 1
    t1.count = 2     // differs -> mixed
    t0.flag  = true
    t1.flag  = false     // differs -> mixed

    let prop = Properties.create(&host.root, {0, 0, 300, 340}, .List)
    var bases: Array'(*u8)
    bases.add(cast(*u8) &t0)
    bases.add(cast(*u8) &t1)
    prop.addStructMulti(MultiTile, bases.toSlice(), "S")
    prop.edView.sendResizeEvent()

    let countItem = findFieldItem(prop, "count")!
    Swag.assert(prop.fieldIsMixed(countItem))
    Swag.assert(countItem.editBox.text() == "")     // blank when mixed

    let flagItem = findFieldItem(prop, "flag")!
    Swag.assert(prop.fieldIsMixed(flagItem))
    Swag.assert(flagItem.checkBox.state == .Indeterminate)     // indeterminate when mixed

    // Editing the mixed native field sets both instances and clears the mixed state.
    countItem.editBox.setText("7")
    prop.validateNative(countItem)
    Swag.assert(t0.count == 7 and t1.count == 7)
    Swag.assert(!prop.fieldIsMixed(countItem))
    Swag.assert(countItem.editBox.text() == "7")
}

// A single instance behaves exactly like the classic addStruct (no multi state).
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 360)
    defer host.shutdown()
    var t0: MultiTile
    t0.count = 3
    let prop = Properties.create(&host.root, {0, 0, 300, 340}, .List)
    var bases: Array'(*u8)
    bases.add(cast(*u8) &t0)
    prop.addStructMulti(MultiTile, bases.toSlice(), "S")
    prop.edView.sendResizeEvent()

    let countItem = findFieldItem(prop, "count")!
    Swag.assert(prop.instanceCount(countItem) == 1)
    Swag.assert(!prop.fieldIsMixed(countItem))
    Swag.assert(countItem.editBox.text() == "3")

    countItem.editBox.setText("8")
    prop.validateNative(countItem)
    Swag.assert(t0.count == 8)
}

func collectEditBoxes(w: *Wnd, out: *Array'(#null *EditBox))
{
    for c in w.children
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
    var host: Testing.HeadlessHost
    host.setup(320, 380)
    defer host.shutdown()
    var t0, t1: MultiTile
    t0.pos = {1, 10}
    t1.pos = {2, 10}     // x differs (mixed), y uniform

    let prop = Properties.create(&host.root, {0, 0, 300, 360}, .List)
    var bases: Array'(*u8)
    bases.add(cast(*u8) &t0)
    bases.add(cast(*u8) &t1)
    prop.addStructMulti(MultiTile, bases.toSlice(), "S")
    prop.edView.sendResizeEvent()

    let posItem = findFieldItem(prop, "pos")!

    // x component differs -> mixed; y component is uniform -> not mixed.
    Swag.assert(prop.subFieldIsMixed(posItem, 0, #sizeof(f32)))
    Swag.assert(!prop.subFieldIsMixed(posItem, #sizeof(f32), #sizeof(f32)))

    var boxes: Array'(#null *EditBox)
    collectEditBoxes(posItem.line, &boxes)
    Swag.assert(boxes.count == 2)     // x and y

    // Set x = 5 on the first component box; both instances get x = 5, y is preserved.
    let box0 = boxes[0]!
    box0.setText("5")
    box0.sigFocusLost.call(box0)
    Swag.assert(t0.pos.x == 5 and t1.pos.x == 5)
    Swag.assert(t0.pos.y == 10 and t1.pos.y == 10)     // untouched
    Swag.assert(!prop.subFieldIsMixed(posItem, 0, #sizeof(f32)))
}

// Enum-flags multi-edit logic: a bit that disagrees across instances is "mixed", and
// setting one flag bit on every instance preserves the other (differing) bits. Exercised
// through the helpers directly because the EnumFlags attribute is not reflected in a
// test-mode build, so the flag rows would not be constructed here (they are in gui4).
#test
{
    var host: Testing.HeadlessHost
    host.setup(200, 120)
    defer host.shutdown()
    let prop = Properties.create(&host.root, {0, 0, 180, 100}, .List)

    var b0, b1: MultiBadges
    b0 = .Star
    b1 = MultiBadges.Star | MultiBadges.Lock     // Star shared, Lock only on b1

    var item: PropertiesItem
    item.type = MultiBadges
    item.dataInstances.add(cast(*u8) &b0)
    item.dataInstances.add(cast(*u8) &b1)

    let starMask = cast(u64) cast(s32) MultiBadges.Star
    let lockMask = cast(u64) cast(s32) MultiBadges.Lock
    let pinMask  = cast(u64) cast(s32) MultiBadges.Pin

    Swag.assert(!prop.flagBitIsMixed(&item, starMask))     // shared -> uniform
    Swag.assert(prop.flagBitIsMixed(&item, lockMask))      // disagrees -> mixed
    Swag.assert(!prop.flagBitIsMixed(&item, pinMask))      // neither has it -> uniform

    // Set Pin on every instance: Lock stays only on b1, Star stays on both.
    prop.writeEnumBit(&item, pinMask, true)
    Swag.assert(cast(bool) (b0 & MultiBadges.Pin) and cast(bool) (b1 & MultiBadges.Pin))
    Swag.assert(!cast(bool) (b0 & MultiBadges.Lock))
    Swag.assert(cast(bool) (b1 & MultiBadges.Lock))
    Swag.assert(cast(bool) (b0 & MultiBadges.Star) and cast(bool) (b1 & MultiBadges.Star))

    // Clearing a shared bit clears it everywhere.
    prop.writeEnumBit(&item, starMask, false)
    Swag.assert(!cast(bool) (b0 & MultiBadges.Star) and !cast(bool) (b1 & MultiBadges.Star))
}

// Dynamic strings are compared and propagated by content (they own a heap buffer).
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 360)
    defer host.shutdown()
    var t0, t1: MultiTile
    t0.name = "alpha"
    t1.name = "beta"     // differs -> mixed

    let prop = Properties.create(&host.root, {0, 0, 300, 340}, .List)
    var bases: Array'(*u8)
    bases.add(cast(*u8) &t0)
    bases.add(cast(*u8) &t1)
    prop.addStructMulti(MultiTile, bases.toSlice(), "S")
    prop.edView.sendResizeEvent()

    let nameItem = findFieldItem(prop, "name")!
    Swag.assert(prop.fieldIsMixed(nameItem))
    Swag.assert(nameItem.editBox.text() == "")

    nameItem.editBox.setText("shared")
    prop.validateDynamicString(nameItem)
    Swag.assert(t0.name == "shared" and t1.name == "shared")
    Swag.assert(!prop.fieldIsMixed(nameItem))

    // Same content in distinct buffers must not read as mixed.
    t0.name = "same"
    t1.name = "same"
    Swag.assert(!prop.fieldIsMixed(nameItem))
}

// A color (struct via the built-in ColorEditor) reports mixed and propagates as a whole value.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 360)
    defer host.shutdown()
    var t0, t1: MultiTile
    t0.tint = Pixel.Argb.Red
    t1.tint = Pixel.Argb.Blue     // differs -> mixed

    let prop = Properties.create(&host.root, {0, 0, 300, 340}, .List)
    var bases: Array'(*u8)
    bases.add(cast(*u8) &t0)
    bases.add(cast(*u8) &t1)
    prop.addStructMulti(MultiTile, bases.toSlice(), "S")
    prop.edView.sendResizeEvent()

    let tintItem = findFieldItem(prop, "tint")!
    Swag.assert(prop.fieldIsMixed(tintItem))

    // Make them equal and refresh: no longer mixed.
    t1.tint = Pixel.Argb.Red
    prop.refresh()
    Swag.assert(!prop.fieldIsMixed(tintItem))
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
    var host: Testing.HeadlessHost
    host.setup(300, 240)
    defer host.shutdown()
    var data: ValData     // name empty -> error, count ok
    let prop = Properties.create(&host.root, {0, 0, 280, 220}, .List)
    prop.addStruct(data, "S")
    prop.edView.sendResizeEvent()

    let nameItem  = findFieldItem(prop, "name")!
    let countItem = findFieldItem(prop, "count")!

    Swag.assert(nameItem.validation == .Error)     // empty name flagged on build
    Swag.assert(nameItem.validationMsg == "Name is required.")
    Swag.assert(countItem.validation == .None)
    Swag.assert(Swag.isSet(nameItem.validationLabel) and nameItem.validationLabel.isVisible())
    Swag.assert(nameItem.validationLabel.textPadding.y > 0)
    Swag.assert(Math.abs(nameItem.validationLabel.textPadding.y + nameItem.validationLabel.textPadding.w) < 0.01)

    // Editing into an invalid range raises a warning.
    countItem.editBox.setText("150")
    prop.validateNative(countItem)
    Swag.assert(data.count == 150)
    Swag.assert(countItem.validation == .Warning)
    Swag.assert(countItem.validationMsg == "Count is unusually large.")

    // Fixing the name clears its error.
    nameItem.editBox.setText("hello")
    prop.validateDynamicString(nameItem)
    Swag.assert(nameItem.validation == .None)
}

// A validation set manually (no notify interface) is kept across refreshes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(280, 220)
    defer host.shutdown()
    var data: PropHeadlessData     // no IPropertyNotify
    let prop = Properties.create(&host.root, {0, 0, 260, 200}, .List)
    prop.addStruct(data)
    prop.edView.sendResizeEvent()

    let it = findFieldItem(prop, "count")!

    prop.setItemValidation(it, .Error, "bad value")
    Swag.assert(it.validation == .Error and it.validationMsg == "bad value")

    // updateValidation must not clobber a manual state when there is no notify interface.
    prop.updateValidation()
    Swag.assert(it.validation == .Error)

    prop.setItemValidation(it, .None)
    Swag.assert(it.validation == .None)
}

// Read-only fields gray (disable) their editor, while staying visible. Covers both the
// ReadOnly attribute and the dynamic isItemReadOnly notify API, including toggling at runtime.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 360)
    defer host.shutdown()
    g_PropRoDynamic = true

    var data: PropHeadlessRoData
    let prop = Properties.create(&host.root, {0, 0, 240, 340})
    prop.addStruct(data)

    let normalItem  = findFieldItem(prop, #nameof(PropHeadlessRoData.normal))!
    let lockedItem  = findFieldItem(prop, #nameof(PropHeadlessRoData.locked))!
    let dynamicItem = findFieldItem(prop, #nameof(PropHeadlessRoData.dynamic))!
    Swag.assert(Swag.isSet(normalItem.editBox) and Swag.isSet(lockedItem.editBox) and Swag.isSet(dynamicItem.editBox))

    // Edit-box editors stay focusable but become read-only. The editable field is not; the
    // read-only fields (attribute + dynamic) are. They are not changeable either.
    Swag.assert(!normalItem.editBox.flags.has(.ReadOnly))
    Swag.assert(lockedItem.editBox.flags.has(.ReadOnly))
    Swag.assert(dynamicItem.editBox.flags.has(.ReadOnly))
    Swag.assert(prop.canChangeItem(normalItem))
    Swag.assert(!prop.canChangeItem(lockedItem))
    Swag.assert(!prop.canChangeItem(dynamicItem))

    // Clearing the dynamic flag releases only that field; the attribute one stays locked.
    g_PropRoDynamic = false
    prop.setCurrentSection(Swag.U32.Max)
    Swag.assert(!dynamicItem.editBox.flags.has(.ReadOnly))
    Swag.assert(prop.canChangeItem(dynamicItem))
    Swag.assert(lockedItem.editBox.flags.has(.ReadOnly))
    Swag.assert(!prop.canChangeItem(lockedItem))
}

// Reordering array elements (static + dynamic) and removing a dynamic element by the correct
// index, including struct arrays whose element rows are interleaved with their field rows.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 520)
    defer host.shutdown()
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

    let dynArr = findFieldItem(prop, #nameof(PropMoveData.dyn))!
    var elems: Array'(#null *PropertiesItem)
    for it in prop.items where it!.parent == dynArr do
        elems.add(it)
    Swag.assert(elems.count == 3)

    // Move element 0 down -> [20,10,30], then element 2 up -> [20,30,10].
    prop.moveArrayValue(elems[0]!, 1)
    Swag.assert(data.dyn[0].id == 20 and data.dyn[1].id == 10 and data.dyn[2].id == 30)
    prop.moveArrayValue(elems[2]!, -1)
    Swag.assert(data.dyn[0].id == 20 and data.dyn[1].id == 30 and data.dyn[2].id == 10)

    // Move at the boundaries is a no-op.
    prop.moveArrayValue(elems[0]!, -1)
    Swag.assert(data.dyn[0].id == 20)

    // Remove the element at index 1 (id 30) -> [20,10]. Used to compute an out-of-bounds index
    // for struct arrays with more than one element.
    prop.removeArrayValue(elems[1]!)
    Swag.assert(data.dyn.count == 2 and data.dyn[0].id == 20 and data.dyn[1].id == 10)

    // Static array reorder: [1,2,3], move index 0 down -> [2,1,3].
    let statArr = findFieldItem(prop, #nameof(PropMoveData.stat))!
    var statElems: Array'(#null *PropertiesItem)
    for it in prop.items where it!.parent == statArr do
        statElems.add(it)
    Swag.assert(statElems.count == 3)
    prop.moveArrayValue(statElems[0]!, 1)
    Swag.assert(data.stat[0] == 2 and data.stat[1] == 1 and data.stat[2] == 3)
}

// The context-menu commands run through the shared gui action system (ActionProperties /
// IActionUI): update() computes each item's enabled state, execute() performs the change via a
// real CommandEvent — no hardcoded result-string switch.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 520)
    defer host.shutdown()
    var data: PropMoveData
    data.dyn.resize(3)
    data.dyn[0].id = 10
    data.dyn[1].id = 20
    data.dyn[2].id = 30

    let prop = Properties.create(&host.root, {0, 0, 280, 500}, .List)
    prop.addStruct(data)

    // Copy the first element's 'id' field (value 10) and read it back from the clipboard.
    let idField = findFieldItem(prop, #nameof(PropMoveElem.id))!
    prop.menuItem = idField
    prop.sendCommandEvent(ActionProperties.Copy)
    var got: s32
    Swag.assert(Clipboard.getTypedValue(&got, idField.type!) and got == 10)

    let dynArr = findFieldItem(prop, #nameof(PropMoveData.dyn))
    var elems: Array'(#null *PropertiesItem)
    for it in prop.items where it!.parent == dynArr do
        elems.add(it)
    Swag.assert(elems.count == 3)

    // update(): Move Up is disabled on the first element, enabled on the second.
    prop.menuItem = elems[0]
    var st = prop.sendComputeCommandStateEvent(ActionProperties.MoveUp)
    Swag.assert(st.updatedFields.has(.Disabled) and st.disabled)
    prop.menuItem = elems[1]
    st            = prop.sendComputeCommandStateEvent(ActionProperties.MoveUp)
    Swag.assert(st.updatedFields.has(.Disabled) and !st.disabled)

    // execute(): Move Up on element 1 reorders the underlying array, dispatched through the real
    // CommandEvent path (sendCommandEvent updates state first, then sends the command).
    prop.sendCommandEvent(ActionProperties.MoveUp)
    Swag.assert(data.dyn[0].id == 20 and data.dyn[1].id == 10 and data.dyn[2].id == 30)
}

// --- Custom editor registry -------------------------------------------------

struct PropHeadlessAngle
{
    deg: s32 = 45
}

struct PropHeadlessAngleData
{
    rot:  PropHeadlessAngle
    name: #null string = "x"
}

var g_PropAngleEditorCalls: s32

// A custom editor for PropHeadlessAngle: a single editbox showing "<deg> deg" instead of
// expanding the struct into its 'deg' sub-field. Implemented as an IPropertyEditor and
// registered globally at #init (below) — the non-intrusive, interface-based registry path
// (the type itself stays untouched).
struct PropAngleEditor {}

impl IPropertyEditor for PropAngleEditor
{
    mtd impl canEdit(type: #null typeinfo)->bool
    {
        return type == PropHeadlessAngle
    }

    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: #null [*] u8, parent: #null *PropertiesItem)->*PropertiesItem
    {
        g_PropAngleEditorCalls += 1

        let item  = list.addItem(value, data, parent)
        let angle = cast(*PropHeadlessAngle) data!

        with let ed = EditBox.create(item.line, "", {0, 0, 120, 24})
        {
            // No numeric input mask: the editor shows a "<deg> deg" suffixed string, so the
            // writer parses the leading number out of the free text.
            .sigFocusLost += func|list, item, angle|(ed)
            {
                angle.deg = cast(s32) (expect StrConv.toNum's64(ed.text()))
                list.commitItemChange(item)
            }
        }

        item.editBox    = ed
        item.sigRefresh += func|angle|(item) { item.editBox.setText(Format.toString("% deg", angle.deg)) }

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
    var host: Testing.HeadlessHost
    host.setup(260, 320)
    defer host.shutdown()
    var data: PropHeadlessAngleData

    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    g_PropAngleEditorCalls = 0
    prop.addStruct(data)

    // The editor ran once for 'rot'; the struct was NOT expanded into a 'deg' child row, so
    // items = [section, rot, name].
    Swag.assert(g_PropAngleEditorCalls == 1)
    Swag.assert(prop.items.count == 3)

    let rot = findFieldItem(prop, #nameof(PropHeadlessAngleData.rot))!
    Swag.assert(Swag.isSet(rot.editBox))
    Swag.assert(rot.numChilds == 0)
    Swag.assert(rot.editBox.text() == "45 deg")

    // A plain field next to it still uses the built-in editor.
    let name = findFieldItem(prop, #nameof(PropHeadlessAngleData.name))
    Swag.assert(name != null and Swag.isSet(name.editBox))

    // The registry resolves the editor for the angle type, but not for an unrelated one.
    Swag.assert(Properties.findEditor(PropHeadlessAngle) != null)
    Swag.assert(Properties.findEditor(#null string) == null)
}

// --- Reset to default -------------------------------------------------------

struct PropDefaultData
{
    count:   s32          = 42
    name:    #null string = "hello"     // static string: read-only, never resettable
    enabled: bool         = true
}

var g_PropDefResetCalls:    s32
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
    var host: Testing.HeadlessHost
    host.setup(260, 320)
    defer host.shutdown()
    var data: PropDefaultData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    let countItem = findFieldItem(prop, #nameof(PropDefaultData.count))!

    // The default value comes from a real default-constructed instance of the struct.
    Swag.assert(countItem.defaultData != null)
    Swag.assert(countItem.defaultData![as s32] == 42)

    // Freshly built: at default -> not modified, no revert button, cannot... still resettable type.
    Swag.assert(!countItem.isModified)
    Swag.assert(prop.canReset(countItem))
    Swag.assert(!Swag.isSet(countItem.revertButton) or !countItem.revertButton.isVisible())

    // Static string field is read-only -> never resettable and never modified.
    let nameItem = findFieldItem(prop, #nameof(PropDefaultData.name))!
    Swag.assert(!prop.canReset(nameItem))
    Swag.assert(!nameItem.isModified)

    // Bool list rows span the whole row (the side description wraps over the control
    // width). List mode has NO revert button: a modified row is marked by the painted
    // vertical accent bar (VSCode-style), and reset lives in the context menu.
    let enabledItem = findFieldItem(prop, #nameof(PropDefaultData.enabled))!
    Swag.assert(Swag.isSet(enabledItem.checkBox))
    data.enabled = false
    prop.updateStates()
    Swag.assert(enabledItem.isModified)
    Swag.assert(!Swag.isSet(enabledItem.revertButton))
    let contentWidth = cast(f32) prop.editorWidth - prop.leftMargin - prop.rightMargin
    Swag.assert(enabledItem.checkBox.parent!.position.width > contentWidth)

    // Edit the value away from its default: the row becomes modified (no button either).
    countItem.editBox.setText("99")
    prop.validateNative(countItem)
    Swag.assert(data.count == 99)
    Swag.assert(countItem.isModified)
    Swag.assert(!Swag.isSet(countItem.revertButton))

    // Reset (the context-menu action path) restores the declared default.
    prop.resetItemDefault(countItem)
    Swag.assert(data.count == 42)
    Swag.assert(!countItem.isModified)
}

// The "Reset to default" context-menu command goes through the shared action system: update()
// disables it while the value is at its default and enables it once modified; execute() resets.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 320)
    defer host.shutdown()
    var data: PropDefaultData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    let countItem = findFieldItem(prop, #nameof(PropDefaultData.count))!
    prop.menuItem = countItem

    // At default: the command exists but is disabled.
    var st = prop.sendComputeCommandStateEvent(ActionProperties.ResetDefault)
    Swag.assert(st.updatedFields.has(.Disabled) and st.disabled)

    // After a change: enabled, and executing it restores the default.
    data.count = 7
    prop.updateStates()
    Swag.assert(countItem.isModified)
    st = prop.sendComputeCommandStateEvent(ActionProperties.ResetDefault)
    Swag.assert(st.updatedFields.has(.Disabled) and !st.disabled)

    prop.sendCommandEvent(ActionProperties.ResetDefault)
    Swag.assert(data.count == 42 and !countItem.isModified)
}

// The test and the reset are both customizable through IPropertyNotify: isItemAtDefault forces the
// modified state (even though the value equals the default), and resetItemToDefault handles reset.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 320)
    defer host.shutdown()
    g_PropDefResetCalls    = 0
    g_PropDefForceModified = true

    var data: PropDefaultCustom
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    let valItem = findFieldItem(prop, #nameof(PropDefaultCustom.val))!

    // Value equals the declared default (5), but the override forces "modified".
    Swag.assert(valItem.data![as s32] == 5)
    Swag.assert(valItem.isModified)

    // Reset is taken over by the notify interface: our handler runs, the built-in copy does not.
    prop.resetItemDefault(valItem)
    Swag.assert(g_PropDefResetCalls == 1)

    // Flipping the override back reports "at default".
    g_PropDefForceModified = false
    prop.updateStates()
    Swag.assert(!valItem.isModified)
}

// Grid mode: the revert column is reserved on the right of every resettable row (docked, present
// even while at default), so the value editor keeps a constant width; toggling the arrow on/off
// never resizes it. Mirrors the Godot/Unreal revert column.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 320)
    defer host.shutdown()
    var data: PropDefaultData
    let prop = Properties.create(&host.root, {0, 0, 340, 300}, .Grid)
    prop.addStruct(data)

    let countItem = findFieldItem(prop, #nameof(PropDefaultData.count))!
    Swag.assert(Swag.isSet(countItem.editBox))

    // The revert arrow is docked to the right of the row (the trailing action margin) and present
    // from the start; while at its default the arrow is hidden (disabled) but the column stays
    // reserved so the editor keeps a constant width.
    let btn = countItem.revertButton
    Swag.assert(btn.dockStyle == .Right)
    Swag.assert(btn.isDisabled())
    let editWidthClean = countItem.editBox.position.width

    // Change the value: the arrow becomes active WITHOUT resizing the editor.
    data.count = 5
    prop.updateStates()
    Swag.assert(countItem.isModified and !btn.isDisabled())
    Swag.assert(countItem.editBox.position.width == editWidthClean)

    // Reset hides the arrow again; the editor width is still unchanged.
    btn.isHot              = true
    btn.isIn               = true
    btn.isPressed          = true
    btn.isPressing         = true
    btn.aniBk.themeCrc     = 42'u32
    host.app.mouseEnterWnd = btn
    host.app.setMouseCaptureRaw(btn)
    prop.resetItemDefault(countItem)
    Swag.assert(!countItem.isModified and btn.isDisabled())
    Swag.assert(countItem.editBox.position.width == editWidthClean)
    Swag.assert(!btn.icon.isValid())
    Swag.assert(!btn.isHot)
    Swag.assert(!btn.isIn)
    Swag.assert(!btn.isPressed)
    Swag.assert(!btn.isPressing)
    Swag.assert(btn.aniBk.themeCrc == Swag.U32.Max)
    Swag.assert(host.app.mouseEnterWnd == null)
    Swag.assert(host.app.mouseCaptureWnd == null)
}

// Condensed grid mode: the revert button is sized to the condensed editor height, then docked
// right; this keeps it vertically centered in the thin row instead of overflowing from the top.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 320)
    defer host.shutdown()
    var data: PropDefaultData
    let prop = Properties.create(&host.root, {0, 0, 340, 300}, .Condensed)
    prop.addStruct(data)

    let countItem = findFieldItem(prop, #nameof(PropDefaultData.count))!
    Swag.assert(Swag.isSet(countItem.revertButton))

    let btn = countItem.revertButton
    Swag.assert(btn.position.height == PropCondensedControlHeight)
    Swag.assert(Math.isEqualEpsilon(btn.position.vertCenter(), countItem.line.clientRect().vertCenter(), 0.01))

    data.count = 5
    prop.updateStates()
    Swag.assert(countItem.isModified and !btn.isDisabled())
    Swag.assert(btn.position.height == PropCondensedControlHeight)
    Swag.assert(Math.isEqualEpsilon(btn.position.vertCenter(), countItem.line.clientRect().vertCenter(), 0.01))
}

// Multi-selection: a field is "modified" when it differs from the default in ANY edited instance,
// and reset writes the declared default into every instance.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 360)
    defer host.shutdown()
    var t0, t1: PropDefaultData
    t0.count = 42     // at default
    t1.count = 7      // differs

    let prop = Properties.create(&host.root, {0, 0, 300, 340}, .List)
    var bases: Array'(*u8)
    bases.add(cast(*u8) &t0)
    bases.add(cast(*u8) &t1)
    prop.addStructMulti(PropDefaultData, bases.toSlice(), "S")

    let countItem = findFieldItem(prop, #nameof(PropDefaultData.count))!
    Swag.assert(countItem.isModified)     // one instance differs

    prop.resetItemDefault(countItem)
    Swag.assert(t0.count == 42 and t1.count == 42)
    Swag.assert(!countItem.isModified)
}

// Undo/redo of a scalar field edit: each commit records one step; undo/redo walk the timeline;
// canUndo/canRedo track the edges; a no-op change records nothing; a new edit after undo drops
// the redo tail.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 320)
    defer host.shutdown()
    var data: PropHeadlessData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)

    let it = findFieldItem(prop, #nameof(PropHeadlessData.count))!
    Swag.assert(!prop.canUndo() and !prop.canRedo())

    // Writing the same value back records nothing.
    it.data![as s32] = 42
    prop.commitItemChange(it)
    Swag.assert(!prop.canUndo())

    // Two real edits.
    it.data![as s32] = 100
    prop.commitItemChange(it)
    Swag.assert(data.count == 100 and prop.canUndo() and !prop.canRedo())

    it.data![as s32] = 7
    prop.commitItemChange(it)
    Swag.assert(data.count == 7)

    prop.undo()
    Swag.assert(data.count == 100 and prop.canUndo() and prop.canRedo())
    prop.undo()
    Swag.assert(data.count == 42 and !prop.canUndo())

    prop.redo()
    Swag.assert(data.count == 100)
    prop.redo()
    Swag.assert(data.count == 7 and !prop.canRedo())

    // New edit after undo truncates the redo tail.
    prop.undo()     // -> 100
    prop.undo()     // -> 42
    it.data![as s32] = 55
    prop.commitItemChange(it)
    Swag.assert(data.count == 55 and !prop.canRedo())
    prop.undo()
    Swag.assert(data.count == 42)
}

// Undo/redo of a dynamic String field (copied by content, not by raw bytes).
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 360)
    defer host.shutdown()
    var data: MultiTile
    data.name = "alpha"
    let prop = Properties.create(&host.root, {0, 0, 280, 340}, .List)
    prop.addStruct(data)

    let it = findFieldItem(prop, #nameof(MultiTile.name))!

    it.data![as String] = "beta"
    prop.commitItemChange(it)
    Swag.assert(data.name == "beta")

    prop.undo()
    Swag.assert(data.name == "alpha")
    prop.redo()
    Swag.assert(data.name == "beta")
}

// Undo/redo across a multi-selection edit restores every edited instance.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 360)
    defer host.shutdown()
    var t0, t1: PropHeadlessData     // both count = 42
    let prop = Properties.create(&host.root, {0, 0, 300, 340}, .List)
    var bases:  Array'(*u8)
    bases.add(cast(*u8) &t0)
    bases.add(cast(*u8) &t1)
    prop.addStructMulti(PropHeadlessData, bases.toSlice(), "S")

    let it = findFieldItem(prop, #nameof(PropHeadlessData.count))!

    it.data![as s32] = 100     // edit instance 0; hasChanged propagates
    prop.commitItemChange(it)
    Swag.assert(t0.count == 100 and t1.count == 100)

    prop.undo()
    Swag.assert(t0.count == 42 and t1.count == 42)
    prop.redo()
    Swag.assert(t0.count == 100 and t1.count == 100)
}

// Ctrl+Z / Ctrl+Y (and Ctrl+Shift+Z) drive undo/redo while the grid is in navigation mode.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 320)
    defer host.shutdown()
    var data: PropHeadlessData
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.addStruct(data)
    prop.focusNavigation()

    let it = findFieldItem(prop, #nameof(PropHeadlessData.count))!
    it.data![as s32] = 100
    prop.commitItemChange(it)
    Swag.assert(data.count == 100)

    host.keyPress(Input.Key.Z, Input.KeyModifiers.Control)
    Swag.assert(data.count == 42)
    host.keyPress(Input.Key.Y, Input.KeyModifiers.Control)
    Swag.assert(data.count == 100)
    host.keyPress(Input.Key.Z, Input.KeyModifiers.Control)
    Swag.assert(data.count == 42)
    host.keyPress(Input.Key.Z, Input.KeyModifiers.Control | Input.KeyModifiers.Shift)
    Swag.assert(data.count == 100)
}

// --- Nested subgroups (#3) and decorators (#5) ------------------------------

struct PropDecorData
{
    #[Category("Transform")]
    px: s32 = 1

    #[Category("Transform/Advanced")]
    shear: s32 = 2

    #[Category("Physics")]
    #[Heading("Body")]
    #[Gap(16)]
    #[HelpBox("Affects simulation")]
    mass: s32 = 3
}

// A "/"-separated Category opens nested subgroups (the shared prefix is reused across siblings),
// and the Heading / Gap / HelpBox decorators inject header / spacer / note rows above the field.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 480)
    defer host.shutdown()
    var data: PropDecorData
    let prop = Properties.create(&host.root, {0, 0, 340, 460}, .Grid)
    prop.addStruct(data, "S")
    prop.edView.sendResizeEvent()

    // Nested categories: Transform is a top-level group (level 0); Advanced is nested under it
    // (level 1, reusing the same Transform header); Physics is a second top-level group (level 0).
    let transform = findFieldItem(prop, "Transform")!
    let advanced  = findFieldItem(prop, "Advanced")!
    let physics   = findFieldItem(prop, "Physics")!
    Swag.assert(transform.flags.has(.Category) and transform.level == 0)
    Swag.assert(advanced.flags.has(.Category) and advanced.level == 1)
    Swag.assert(physics.flags.has(.Category) and physics.level == 0)
    Swag.assert(advanced.parent == transform)     // subgroup nested under its prefix

    // Fields indent with their group depth: a top-level field is at indent 0, a subgroup field one
    // step further, and the subgroup header lines up with the fields it groups.
    let px    = findFieldItem(prop, #nameof(PropDecorData.px))!
    let shear = findFieldItem(prop, #nameof(PropDecorData.shear))!
    Swag.assert(prop.itemIndent(px) == 0)
    Swag.assert(prop.itemIndent(transform) == 0)
    Swag.assert(prop.itemIndent(shear) > prop.itemIndent(px))
    Swag.assert(prop.itemIndent(advanced) == prop.itemIndent(shear))     // subgroup header aligns with its field

    // The three decorators on 'mass' produced three extra rows before it, all under Physics.
    var spacer, heading, note: #null *PropertiesItem
    for it in prop.items
    {
        let item = it!
        if item.flags.has(.Spacer) do
            spacer = item
        if item.flags.has(.Header) do
            heading = item
        if item.flags.has(.Note) do
            note = item
    }

    let spacerIt  = spacer!
    let headingIt = heading!
    let noteIt    = note!
    Swag.assert(headingIt.parent == physics and spacerIt.parent == physics and noteIt.parent == physics)
    Swag.assert(headingIt.typeValue.name == "Body")
    Swag.assert(spacerIt.line.position.height == 16)     // Gap(16)
    Swag.assert(Swag.isSet(noteIt.label))                // the info bar label

    // Decorators are inert: not focusable and never expandable.
    Swag.assert(headingIt.flags.has(.NoFocus) and spacerIt.flags.has(.NoFocus) and noteIt.flags.has(.NoFocus))
    Swag.assert(headingIt.numChilds == 0 and spacerIt.numChilds == 0 and noteIt.numChilds == 0)
}

struct PropHeadlessFontStyleData
{
    style = Pixel.FontFamilyStyle.Regular
}

struct PropHeadlessPanelStringData
{
    #[Properties.Name("Dynamic text")]
    dynamic: String

    #[Properties.Name("Fixed text")]
    fixed: string = "Read only"
}

// Panel string fields keep a persistent, aligned label. A placeholder stops naming a field as
// soon as it contains a value, and the static-string variant must not fall back to a stacked row.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 260)
    defer host.shutdown()

    var data: PropHeadlessPanelStringData
    data.dynamic = "Editable"
    let prop = Properties.create(&host.root, {0, 0, 300, 240}, kind: .Panel)
    prop.addStruct(data)
    host.root.applyLayout()
    host.pump()

    let dynamic     = findFieldItem(prop, #nameof(PropHeadlessPanelStringData.dynamic))!
    let fixed       = findFieldItem(prop, #nameof(PropHeadlessPanelStringData.fixed))!
    let dynamicCtrl = cast(*EditCtrl) dynamic.line.children[1]
    let fixedCtrl   = cast(*EditCtrl) fixed.line.children[1]
    Swag.assert(!dynamic.label.isVisible() and !fixed.label.isVisible())
    Swag.assert(dynamicCtrl.label.text() == "Dynamic text" and fixedCtrl.label.text() == "Fixed text")
    Swag.assert(dynamicCtrl.label.position.width == fixedCtrl.label.position.width)
    Swag.assert(dynamicCtrl.edit.position.x == fixedCtrl.edit.position.x)
    Swag.assert(dynamicCtrl.edit.text() == "Editable" and fixedCtrl.edit.text() == "Read only")
    Swag.assert(fixedCtrl.edit.flags.has(.ReadOnly))
}

// The bold/italic buttons of the FontFamilyStyle editor are independent toggles: a
// second click on a checked button must uncheck it (regression: with Radio the
// click on a checked button was swallowed, so bold/italic could never be removed).
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 320)
    defer host.shutdown()
    var data: PropHeadlessFontStyleData
    let prop = Properties.create(&host.root, {0, 0, 240, 300}, kind: .Panel)
    prop.addStruct(data)
    host.root.applyLayout()
    host.pump()

    // items[0] is the implicit section. In Panel mode the persistent field label is the
    // first child, followed by the sub-line that stacks the B and I buttons.
    let item      = prop.items[1]!
    let stack     = item.line.children[1]
    let btnBold   = cast(*IconButton) stack.children[0]
    let btnItalic = cast(*IconButton) stack.children[1]

    host.clickWnd(btnBold)
    Swag.assert(data.style == .Bold)
    host.clickWnd(btnItalic)
    Swag.assert(data.style == .BoldItalic)
    host.clickWnd(btnBold)
    Swag.assert(data.style == .Italic)
    host.clickWnd(btnItalic)
    Swag.assert(data.style == .Regular)
}

struct PropHeadlessUsingBase
{
    baseVal: s32
}

struct PropHeadlessUsingDerived
{
    using base: PropHeadlessUsingBase
    ownVal:     s32
}

// usingFieldsLast walks the struct's own fields before recursing into its 'using'
// bases, so a derived type edits its most specific fields first.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 320)
    defer host.shutdown()

    func indexOf(prop: *Properties, name: string)->u64
    {
        for item, idx in prop.items
        {
            if item!.typeValue.name == name do
                return idx
        }

        Swag.assert(false)
        return 0
    }

    var data: PropHeadlessUsingDerived

    // Declaration order by default: the 'using' base fields come first
    let prop0 = Properties.create(&host.root, {0, 0, 240, 300})
    prop0.addStruct(data)
    Swag.assert(indexOf(prop0, "baseVal") < indexOf(prop0, "ownVal"))

    // Most specific first with usingFieldsLast
    let prop1 = Properties.create(&host.root, {0, 0, 240, 300})
    prop1.setUsingFieldsLast(true)
    prop1.addStruct(data)
    Swag.assert(indexOf(prop1, "ownVal") < indexOf(prop1, "baseVal"))
}

enum PropFilterChoice
{
    Hidden
    Low
    Medium
    High
}

struct PropFilterData
{
    choice = PropFilterChoice.Medium
}

struct PropFilterHost {}

impl IPropertyNotify for PropFilterHost
{
    mtd impl isEnumValueVisible(list: *Properties, item: *PropertiesItem, enumValue: Swag.TypeValue)->bool
    {
        return enumValue.name != "Hidden"
    }
}

// The host notify can hide enum values (isEnumValueVisible): the combo omits them and
// the selection/write-back mapping stays correct through the remaining entries.
#test
{
    var host: Testing.HeadlessHost
    host.setup(260, 320)
    defer host.shutdown()
    var data: PropFilterData
    var ntfy: PropFilterHost
    let prop = Properties.create(&host.root, {0, 0, 240, 300})
    prop.setNotify(&ntfy)
    prop.addStruct(data)

    let item = prop.items[1]!
    Swag.assert(Swag.isSet(item.comboBox))
    Swag.assert(item.comboBox.items.count == 3)

    // Medium is enum value 2 but combo slot 1 (Hidden is filtered out)
    Swag.assert(item.comboBox.selectedIndex == 1)

    // Selecting the last combo slot writes the matching enum value back
    item.comboBox.setSelectedIndex(2)
    Swag.assert(data.choice == .High)
    item.comboBox.setSelectedIndex(0)
    Swag.assert(data.choice == .Low)
}

// A String field naming a document, and one holding free text beside it.
struct PropDropData
{
    #[Properties.Name("Source"), Properties.FilePath]
    source: String

    #[Properties.Name("Note")]
    note: String
}

// A file dropped on a FilePath field fills it, and commits with the focus like a typed value.
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 200)
    defer host.shutdown()

    var data: PropDropData
    let prop = Properties.create(&host.root, {0, 0, 420, 200}, .List)
    prop.addStruct(data, "S")
    prop.edView.sendResizeEvent()
    host.root.applyLayout()
    host.pump()

    let sourceItem = findFieldItem(prop, "source")!
    let noteItem   = findFieldItem(prop, "note")!

    Swag.assert(host.dropFilesOnWnd(sourceItem.editBox, ["c:/assets/mesh.obj"]) == DropEffect.Copy)
    Swag.assert(sourceItem.editBox.text() == "c:/assets/mesh.obj")

    // The editor holds it until the focus leaves, which is when a typed value lands too.
    prop.validateDynamicString(sourceItem)
    Swag.assert(data.source == "c:/assets/mesh.obj")

    // A field that did not ask for paths refuses them and keeps what it had.
    Swag.assert(host.dropFilesOnWnd(noteItem.editBox, ["c:/assets/mesh.obj"]) == DropEffect.None)
    Swag.assert(noteItem.editBox.text() == "")
}

struct PropSameCategData
{
    #[Properties.Category("Debug"), Properties.Name("First"), Properties.Description("A long description that should wrap over the full control width, not over the value column")]
    first: bool
    #[Properties.Category("Debug"), Properties.Name("Second")]
    second: bool
    #[Properties.Category("Debug"), Properties.Name("Third")]
    third: bool
}

// Consecutive fields sharing the same Category reuse the open header instead of
// creating new segments (regression: the empty 'until' range used to panic).
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    defer host.shutdown()
    var data: PropSameCategData
    let opt = PropertiesCtrl.create(&host.root, flags: .SectionTabs | .SearchBar)
    opt.dockStyle = .Center
    opt.addStruct(data, "Application")

    host.root.applyLayout()
    host.pump()

    // One section + one category header + the three fields
    var categs = 0
    for item in opt.properties.items
    {
        if item!.flags.has(.Category) do
            categs += 1
    }

    Swag.assert(categs == 1)
    Swag.assert(opt.properties.items.count == 5)

    // The bool description spans the control width, not the value column
    var descItem: #null *PropertiesItem
    for item in opt.properties.items
    {
        if item!.typeValue.name == "first" do
            descItem = item
    }

    let descIt = descItem!
    Swag.assert(Swag.isSet(descIt.checkBox))
    Swag.assert(descIt.checkBox.parent!.position.width > cast(f32) opt.properties.editorWidth)
}

enum PropAlignChoice { A, B, C }

struct PropAlignData
{
    #[Properties.Name("Slide"), Properties.SliderMinMax(0, 100)]
    slide: f32 = 10
    #[Properties.Name("Choice")]
    choice = PropAlignChoice.A
    #[Properties.Name("Count")]
    count: s32 = 5
}

// List mode: every value editor (slider, combo, edit box) shares the same fixed edit
// width, so their right edges line up — and stay lined up after the control is resized
// (regression: anchored widths drifted with the resize history).
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    defer host.shutdown()
    var data: PropAlignData
    let prop = Properties.create(&host.root, {0, 0, 400, 560}, .List)
    prop.addStruct(data, "S")
    host.root.applyLayout()
    host.pump()

    func assertAligned(prop: *Properties)
    {
        var right = -1.0'f32
        for item in prop.items
        {
            let it = item!
            var w: #null *Wnd
            if Swag.isSet(it.sliderBox) do
                w = it.sliderBox
            elif Swag.isSet(it.comboBox) do
                w = it.comboBox
            elif Swag.isSet(it.editBox) do
                w = it.editBox
            if !w do
                continue

            let wnd = w!
            if right < 0 do
                right = wnd.position.right()
            Swag.assert(Math.isEqualEpsilon(wnd.position.right(), right, 0.01))
        }

        Swag.assert(right > 0)
    }

    assertAligned(prop)

    // Grow then shrink the control: the editors must not drift
    prop.setPosition({0, 0, 760, 560})
    host.root.applyLayout()
    host.pump()
    assertAligned(prop)

    prop.setPosition({0, 0, 300, 560})
    host.root.applyLayout()
    host.pump()
    assertAligned(prop)
}

// A field the resolver claims shows its answer; a field it declines keeps the declared
// wording, and the module's own strings answer after it.
#test
{
    // Whatever this test installs, the next one starts with the declared strings.
    defer Properties.setTextResolver(null)

    Swag.assert(Properties.resolveText("Thickness") == "Thickness")

    Properties.setTextResolver(func(key: string)->#null string
    {
        switch key
        {
        case "Thickness": return "Epaisseur"
        case "Debug":     return "Diagnostics"
        }

        return null
    })

    Swag.assert(Properties.resolveText("Thickness") == "Epaisseur")
    Swag.assert(Properties.resolveText("Count") == "Count")

    // An installed resolver outranks the module's own wording for the same key, and the
    // module still answers for the keys the resolver declines.
    Swag.assert(Properties.resolveText("Debug") == "Diagnostics")
    Swag.assert(Properties.resolveText("Show Clip Rect") == strings().prop_ShowClipRect)

    Properties.setTextResolver(null)
    Swag.assert(Properties.resolveText("Thickness") == "Thickness")
}

// Every generated row goes through the resolver: the field label, the category header,
// and the two entries of a boolean combo.
#test
{
    defer Properties.setTextResolver(null)
    Properties.setTextResolver(func(key: string)->#null string
    {
        switch key
        {
        case "Numbers":  return "Nombres"
        case "Count":    return "Nombre"
        case "Straight": return "Droite"
        case "Bezier":   return "Courbe"
        }

        return null
    })

    var host: Testing.HeadlessHost
    host.setup(600, 400)
    defer host.shutdown()

    var data: PropHeadlessResolvedData
    let prop = Properties.create(&host.root, {0, 0, 560, 360})
    prop.addStruct(data)
    host.root.applyLayout()
    host.pump()

    var sawCategory, sawLabel, sawCombo = false
    for item in prop.items
    {
        let it = item!
        if !Swag.isSet(it.label) do
            continue
        if it.label.text() == "Nombres" do
            sawCategory = true
        if it.label.text() == "Nombre" do
            sawLabel = true
        if Swag.isSet(it.comboBox) and it.comboBox.items.count == 2 and it.comboBox.items[0]!.name.raw == "Droite" do
            sawCombo = true
    }

    Swag.assert(sawCategory)
    Swag.assert(sawLabel)
    Swag.assert(sawCombo)
}

// Filtering is stronger than the persisted disclosure state: a match remains reachable through
// a collapsed branch, and clearing the query restores that branch to its previous state.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 320)
    defer host.shutdown()

    var data: PropHeadlessGroupedData
    let prop = Properties.create(&host.root, {0, 0, 340, 300}, .Grid)
    prop.addStruct(data, "Settings")

    let numbers = findFieldItem(prop, "Numbers")!
    let count   = findFieldItem(prop, #nameof(PropHeadlessGroupedData.count))!
    prop.collapseAll()
    Swag.assert(!numbers.flags.has(.Expanded) and !count.line.isVisible())

    prop.setFilter("Count")
    Swag.assert(numbers.line.isVisible() and count.line.isVisible())
    Swag.assert(!numbers.flags.has(.Expanded))

    prop.setFilter("")
    Swag.assert(!numbers.flags.has(.Expanded) and !count.line.isVisible())
}

// The modified-only view composes with default tracking and updates immediately when an edit is
// reset. expandModified opens only the path that contains the changed field.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 360)
    defer host.shutdown()

    var data: PropHeadlessGroupedData
    let prop = Properties.create(&host.root, {0, 0, 340, 340}, .Grid)
    prop.addStruct(data, "Settings")

    let count   = findFieldItem(prop, #nameof(PropHeadlessGroupedData.count))!
    let enabled = findFieldItem(prop, #nameof(PropHeadlessGroupedData.enabled))!
    let numbers = findFieldItem(prop, "Numbers")!
    let flags   = findFieldItem(prop, "Flags")!

    data.enabled = false
    prop.updateStates()
    Swag.assert(enabled.isModified and !count.isModified)

    prop.collapseAll()
    prop.expandModified()
    Swag.assert(!numbers.flags.has(.Expanded) and flags.flags.has(.Expanded))
    Swag.assert(!count.line.isVisible() and enabled.line.isVisible())

    prop.expandAll()
    Swag.assert(count.line.isVisible() and enabled.line.isVisible())

    prop.setModifiedOnly(true)
    Swag.assert(prop.modifiedOnly)
    Swag.assert(!count.line.isVisible() and enabled.line.isVisible())

    prop.resetItemDefault(enabled)
    Swag.assert(!enabled.isModified and !enabled.line.isVisible())
    prop.setModifiedOnly(false)
    Swag.assert(count.line.isVisible() and enabled.line.isVisible())
}

enum PropGoldenChoice
{
    Automatic
    Manual
    Disabled
}

struct PropGoldenData
{
    #[Category("Appearance"), Name("Visible"), Description("Shows the element in the composed scene.")]
    visible: bool = true

    #[Category("Appearance"), Name("Opacity"), SliderMinMax(0, 1)]
    opacity: f32 = 0.75

    #[Category("Appearance"), Name("Tint")]
    tint: Pixel.Color = 0xFF38BDF8

    #[Category("Layout"), Name("Offset")]
    offset: Math.Point = {12, 8}

    #[Category("Layout"), Name("Mode")]
    mode = PropGoldenChoice.Automatic
}

// Each presentation is a separate rendering contract. In particular, Condensed owns a flat,
// edge-to-edge editor layout and must not silently inherit the normal grid's spacing or chrome.
func assertPropertyPresentationGolden(kind: PropertiesKind, name: string)
{
    var host: Testing.HeadlessHost
    host.setup(520, 620)
    defer host.shutdown()

    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    var data: PropGoldenData
    data.opacity = 0.4

    let ctrl = PropertiesCtrl.create(&host.root, kind: kind, flags: .SearchBar)
    ctrl.dockStyle = .Center
    ctrl.properties.setEditorWidth(280)
    if ctrl.properties.isGridLike() do
        ctrl.properties.setNameColumnWidth(150)
    ctrl.addStruct(data, "Inspector")

    host.root.applyLayout()
    host.pump()
    ctrl.properties.setSelItem(findFieldItem(ctrl.properties, #nameof(PropGoldenData.visible)))
    ctrl.properties.focusNavigation()
    host.settleAnimations(ctrl, 6)

    let image = host.render()
    Pixel.Testing.assertImageGolden(&image, name)
}

#[Swag.TestTag("golden")]
#test { assertPropertyPresentationGolden(.Grid, "properties.grid") }
#[Swag.TestTag("golden")]
#test { assertPropertyPresentationGolden(.Condensed, "properties.condensed") }
#[Swag.TestTag("golden")]
#test { assertPropertyPresentationGolden(.List, "properties.list") }
#[Swag.TestTag("golden")]
#test { assertPropertyPresentationGolden(.Panel, "properties.panel") }
