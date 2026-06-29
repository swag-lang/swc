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

// Editing a slider row: Enter focuses the slider, Left/Right reach the editor and
// change the value (auto-commit model), Down commits and moves to the next row.
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

    // Enter opens the drop-down popup and gives it the keyboard focus.
    host.keyPress(Input.Key.Return)
    @assert(combo.popup != null)
    @assert(host.app.keybFocusWnd == cast(*Wnd) combo.popup.scrollWnd.view)

    // Highlight the next item and commit it; the value writes back to the data and
    // the focus returns to the grid.
    host.keyPress(Input.Key.Down)           // Mid -> High
    host.keyPress(Input.Key.Return)         // commit High
    host.pump()
    @assert(combo.selectedIdx == 2)
    @assert(data.choice == .High)
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
