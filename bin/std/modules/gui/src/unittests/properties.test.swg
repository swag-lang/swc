#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core

struct PropHeadlessData
{
    count:      s32 = 42
    label:      string = "hello"
    enabled:    bool = true
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
