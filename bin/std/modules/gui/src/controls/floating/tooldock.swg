#global public

using Core, Pixel

// Holds the tools of a window in a vertical floating column at its leading edge.
//
// This is the dock of the charter: the surface ground on the menu corner, one square cell of
// [[Gui.ThemeMetrics.toolDock_CellSize]] per tool with a glyph of
// [[Gui.ThemeMetrics.toolDock_Glyph]], [[Gui.ThemeMetrics.floating_Inset]] from the leading edge
// of its parent and vertically centred on it. The dock floats over the work
// ([[Gui.DockStyle.Float]]) and takes no room from it.
//
// At most one tool is active. It sits on the Arc selection ground with an Arc glyph; pressing a
// tool makes it the active one and emits [[Gui.ToolDock.sigToolChanged]]. A tool created with an
// identifier also posts that command, like any icon button.
//
// A cell can stand for a group of tools ([[Gui.ToolDock.addToGroup]]): it shows the one chosen
// last and carries a small mark in its corner; a click on the mark, or a right click on the cell,
// lists the group, and choosing a tool there puts it in the cell and makes it the active one.
//
// ```swag
// with let dock = ToolDock.create(view)
// {
//     .addTool(theme.icon(.Edit, 18), "capture.tool.select", "Select")
//     .addTool(theme.icon(.Plus, 18), "capture.tool.rectangle", "Rectangle")
//     .sigToolChanged += func(_, tool) { Console.print(tool.id) }
// }
// ```
struct ToolDock
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        sigToolChanged: SigArray'func||(*ToolDock, *IconButton)     // Emitted after the reader makes another tool the active one.

        readonly
        {
            tools: Array'(*IconButton)     // Tools in display order, from the top.
        }
    }

    groups: Array'ToolDockGroup
}

// One tool of a group of a [[Gui.ToolDock]] cell.
struct ToolDockMember
{
    icon:    Icon
    id:      WndId?
    toolTip: String
}

// The tools one cell of a [[Gui.ToolDock]] stands for.
struct ToolDockGroup
{
    late cell: *IconButton
    members: Array'ToolDockMember
}

// The side of the corner of a group cell its mark is drawn in; a click there lists the group.
const ToolDockMarkSize = 9.0

impl IWnd for ToolDock
{
    mtd impl onLayout()
    {
        let parent = .parent
        if not parent do
            return

        let metrics = .themeMetrics()
        let bounds  = parent.clientRect()
        let body    = .bodySize()
        let x       = bounds.x + metrics.floating_Inset
        let y       = Math.round(bounds.vertCenter() - body.y * 0.5)
        liftFloating(me)
        .setPosition(Math.Rectangle{x, y, body.x, body.y})

        var cell = Math.Rectangle{metrics.toolDock_Padding, metrics.toolDock_Padding, metrics.toolDock_CellSize, metrics.toolDock_CellSize}
        for tool in .tools
        {
            tool.setPosition(cell)
            cell.y += metrics.toolDock_CellSize + metrics.toolDock_Gap
        }
    }

    mtd impl onBeforePaint(evt: *PaintEvent)
    {
        paintFloatingShadow(me, evt.paintContext.painter, .clientRect(), .themeMetrics().corner_Menu)
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        paintFloatingGround(me, evt.paintContext.painter, .clientRect(), .themeMetrics().corner_Menu)
    }

    // A cell standing for a group carries a small mark in its corner, over its ground.
    mtd impl onAfterPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let ink     = .themeColors().faintText
        painter.setParams(.Antialiased)
        for &group in .groups
        {
            let r  = group.cell.position
            let x1 = r.right() - 3
            let y1 = r.bottom() - 3
            let s  = ToolDockMarkSize * 0.55
            var mark = [Math.Vector2{x1, y1 - s}, Math.Vector2{x1, y1}, Math.Vector2{x1 - s, y1}]
            painter.fillPolygon(mark, Brush.createSolid(ink))
        }
    }
}

impl ToolDock
{
    // Creates an empty dock floating over `parent`.
    #[Swag.Discardable]
    func create(parent: *Wnd, id: WndId? = null)->*ToolDock
    {
        with let result = Wnd.create'ToolDock(parent, null, {}, id)
        {
            .dockStyle       = .Float
            .backgroundStyle = .Transparent
            .wndFlags.add(.AfterChildrenPaint)
        }

        return result
    }

    // Appends a tool and returns its button.
    //
    // The glyph is drawn at [[Gui.ThemeMetrics.toolDock_Glyph]]; `toolTip` names the tool, since
    // the dock writes no word beside a glyph. The first tool added becomes the active one.
    #[Swag.Discardable]
    mtd addTool(icon: Icon, id: WndId? = null, toolTip: string? = null)->*IconButton
    {
        let metrics = .themeMetrics()
        var glyph   = icon
        glyph.sizeX, glyph.sizeY = metrics.toolDock_Glyph

        with let tool = IconButton.create(me, glyph, {0, 0, metrics.toolDock_CellSize, metrics.toolDock_CellSize}, id, .Radio | .IconOnly)
        {
            .setForm(.RoundedRectangle)
            .setCheckIndicator(.Frame)
            .toolTip = toolTip orelse ""
            .sigCheckedChanged += func|dock = me|(button)
            {
                if button.isChecked do
                    dock.activate(button, notify: true)
            }
        }

        .tools.add(tool)
        if .tools.count == 1 do
            tool.setChecked(true)
        .itf.onLayout()
        return tool
    }

    // Adds a tool to the group the cell `cell` stands for; the cell shows the tool it holds now
    // until another of its group is chosen. The tool keeps its command and its key: the dock
    // shows it in the cell when it becomes the active one through them ([[Gui.ToolDock.selectTool]]).
    mtd addToGroup(cell: *IconButton, icon: Icon, id: WndId? = null, toolTip: string? = null)
    {
        Swag.assert(.tools.contains(cell), "the cell belongs to another dock")
        if not .groupOf(cell)
        {
            let added = .groups.emplaceInitAddress()
            added.cell = cell
            added.members.add(ToolDockMember{cell.icon, cell.id, String.from(cell.toolTip)})
            cell.hookOnEvent = func|dock = me|(wnd, evt)->bool => dock.groupCellEvent(assume cast(*IconButton, wnd), evt)
        }

        let group   = unwrap .groupOf(cell)
        let metrics = .themeMetrics()
        var glyph   = icon
        glyph.sizeX, glyph.sizeY = metrics.toolDock_Glyph
        group.members.add(ToolDockMember{glyph, id, String.from(toolTip orelse "")})
        .invalidate()
    }

    // Makes the tool with the command `id` the active one, without emitting
    // [[Gui.ToolDock.sigToolChanged]]: a tool of a group comes into the cell of its group. Returns
    // false when no tool of the dock has that command.
    mtd selectTool(id: WndId)->bool
    {
        for tool in .tools where tool.id == id
        {
            .activate(tool, notify: false)
            return true
        }

        for &group in .groups
        {
            for &member in group.members where member.id == id
            {
                .showMember(group, member)
                .activate(group.cell, notify: false)
                return true
            }
        }

        return false
    }

    // Lists the group of the cell `cell` beside it; the tool chosen there comes into the cell,
    // becomes the active one, and posts its command.
    mtd openGroup(cell: *IconButton)
    {
        let group = .groupOf(cell)
        if not group do
            return

        with let menu = MenuCtrl.createPopup(me)
        {
            for &member in group.members
            {
                // A tool with no words of its own is named by its command.
                if member.toolTip.isEmpty() and member.id do
                    discard .addItem(null, member.id, member.icon, checked: member.id == cell.id)
                else do
                    discard .addItem(member.toolTip, member.id orelse "", member.icon, checked: member.id == cell.id)
            }
        }

        let at     = cell.surfaceRect()
        let result = menu.doModal(Math.Point{at.right() + .themeMetrics().toolDock_Padding, at.y}, autoDestroy: true)
        if not result do
            return
        .chooseInGroup(cell, result)
    }

    // Puts the tool of the group of `cell` with the command `id` in the cell, makes it the active
    // one and posts its command, as choosing it in the list of the group does.
    mtd chooseInGroup(cell: *IconButton, id: WndId)
    {
        let group = .groupOf(cell)
        if not group do
            return
        for &member in group.members where member.id == id
        {
            .showMember(group, member)
            .activate(cell, notify: true)
            cell.postCommandEvent(id)
            break
        }
    }

    // Returns the active tool, or `null` when the dock is empty.
    mtd activeTool()->*IconButton?
    {
        for tool in .tools where tool.isChecked do
            return tool
        return null
    }

    // Makes `tool` the active one without emitting [[Gui.ToolDock.sigToolChanged]].
    mtd setActiveTool(tool: *IconButton)
    {
        Swag.assert(.tools.contains(tool), "the tool belongs to another dock")
        .activate(tool, notify: false)
    }

    // Returns the size of the column; its shadow falls outside it.

    mtd bodySize()->Math.Point
    {
        let metrics = .themeMetrics()
        let count   = cast(f32, .tools.count)
        let gaps    = .tools.count > 1 ? count - 1 : 0
        let height  = count * metrics.toolDock_CellSize + gaps * metrics.toolDock_Gap + 2 * metrics.toolDock_Padding
        return {metrics.toolDock_CellSize + 2 * metrics.toolDock_Padding, height}
    }

    // Returns the group the cell `cell` stands for, or null.
    private mtd groupOf(cell: *IconButton)->*ToolDockGroup?
    {
        for &group in .groups where group.cell == cell do
            return group
        return null
    }

    // Puts `member` in the cell of `group`.
    private mtd showMember(group: *ToolDockGroup, member: *ToolDockMember)
    {
        let cell = group.cell
        cell.setIcon(member.icon)
        cell.id      = member.id
        cell.toolTip = member.toolTip
        cell.invalidate()
    }

    // A click on the mark of a group cell, or a right click on it, lists its group.
    private mtd groupCellEvent(cell: *IconButton, evt: IEvent)->bool
    {
        if evt is MouseEvent as mouse where mouse.kind == .Pressed
        {
            let pos    = cell.surfaceToLocal(mouse.surfacePos)
            let inMark = pos.x >= cell.position.width - ToolDockMarkSize - 3 and pos.y >= cell.position.height - ToolDockMarkSize - 3
            if mouse.button == .Right or (mouse.button == .Left and inMark)
            {
                .openGroup(cell)
                mouse.accepted = true
                return true
            }
        }

        return false
    }

    private mtd activate(tool: *IconButton, notify: bool)
    {
        for other in .tools where other != tool and other.isChecked do
            other.setChecked(false)
        if not tool.isChecked do
            tool.setChecked(true)
        if notify do
            .sigToolChanged.call(me, tool)
    }
}
