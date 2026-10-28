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
}

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
