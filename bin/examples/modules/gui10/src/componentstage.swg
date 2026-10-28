// The floating components of the charter, composed over a piece of work.
//
// The widget wall shows the controls one by one; the components are judged in place, floating
// over something they cover: the dock at the leading edge, the mini-bar beside a selection, the
// inspector at the trailing edge, the hint line at the foot, and the lens over all of it. The
// sheet takes the place of the inspector on `I`.

using Core, Gui, Pixel

const StageOpenLens  = "gui10.stage.lens"
const StageSheet     = "gui10.stage.sheet"
const StageInspector = "gui10.stage.inspector"
const StageSelect    = "gui10.stage.select"
const StageArrow     = "gui10.stage.arrow"
const StageText      = "gui10.stage.text"

// A stage holding the floating components over a sheet of paper standing for the work.
struct ComponentStage
{
    using wnd: Wnd

    late
    {
        work:      *Wnd
        dock:      *ToolDock
        miniBar:   *MiniBar
        inspector: *Inspector
        sheet:     *InfoSheet
        hint:      *HintLine
        lens:      *Lens.View
    }
}

impl IWnd for ComponentStage
{
    // The work stands in the middle; the mini-bar follows the selection drawn on it.
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        // The window is resized once while it is created, before its parts exist.
        if .miniBar == null do
            return

        let client = .clientRect()
        .work.setPosition(Math.Rectangle{client.width * 0.18, client.height * 0.14, client.width * 0.42, client.height * 0.62})
        .miniBar.showNear(.selection())
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        if .work == null do
            return

        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        var mark    = .selection()
        mark.inflate(-0.5)
        painter.drawRect(mark, colors.arc, 1)
    }

    mtd impl onComputeStateEvent(evt: *CommandStateEvent)
    {
        switch evt.id
        {
        case StageOpenLens:
            evt.name = "Open the Lens"

        case StageSheet:
            evt.name = "Show the Sheet"

        case StageInspector:
            evt.name = "Fold the Inspector"

        case StageSelect:
            evt.name = "Select Tool"

        case StageArrow:
            evt.name = "Arrow Tool"

        case StageText:
            evt.name = "Text Tool"

        default:
            evt.accepted = false
            return
        }

        evt.updatedFields.add(.Name)
        evt.accepted = true
    }

    mtd impl onCommandEvent(evt: *CommandEvent)
    {
        switch evt.id
        {
        case StageOpenLens:
            .lens.open()

        case StageSheet:
            .toggleSheet()

        case StageInspector:
            .inspector.toggleFolded()

        case StageSelect:
            .dock.setActiveTool(.dock.tools[0])

        case StageArrow:
            .dock.setActiveTool(.dock.tools[1])

        case StageText:
            .dock.setActiveTool(.dock.tools[2])

        default:
            evt.accepted = false
            return
        }

        evt.accepted = true
    }
}

impl ComponentStage
{
    func create(parent: *Wnd)->*ComponentStage
    {
        with let result = Wnd.create'ComponentStage(parent, {})
        {
            .backgroundStyle = .Window
            .wndFlags.add(.ClipChildren)
            .registerKeyShortcut(.Control, .K, StageOpenLens)
            .registerKeyShortcut(.None, .I, StageSheet)
        }

        with result.work = Wnd.create'Wnd(result, {})
        {
            .backgroundStyle = .Dialog
        }

        result.createDock()
        result.createMiniBar()
        result.createInspector()
        result.createSheet()
        result.createHint()
        result.createLens()
        return result
    }

    // Opens the sheet in place of the inspector, and gives the inspector back when it closes.
    mtd toggleSheet()
    {
        .sheet.toggle()
        .inspector.show(not .sheet.isLocallyVisible())
    }

    private mtd selection()->Math.Rectangle
    {
        let work = .work.position
        return {work.x + work.width * 0.3, work.y + work.height * 0.45, work.width * 0.4, work.height * 0.2}
    }

    private mtd createDock()
    {
        let theme = .theme()
        with .dock = ToolDock.create(me)
        {
            discard .addTool(theme.icon(.Edit, 18), StageSelect, "Select")
            discard .addTool(theme.icon(.Link, 18), StageArrow, "Arrow")
            discard .addTool(theme.icon(.Plus, 18), StageText, "Text")
            discard .addTool(theme.icon(.Picker, 18), toolTip: "Pick a color")
        }
    }

    private mtd createMiniBar()
    {
        let theme = .theme()
        with .miniBar = MiniBar.create(me)
        {
            discard .addButton(theme.icon(.Copy, 16), toolTip: "Copy")
            discard .addButton(theme.icon(.Duplicate, 16), toolTip: "Duplicate")
            .addSeparator()
            discard .addTextButton("Group")
            discard .addButton(theme.icon(.More, 16), StageInspector, "Properties")
        }
    }

    private mtd createInspector()
    {
        with .inspector = Inspector.create(me)
        {
            .setTitle("Arrow", "1 object")
            discard .addAction("Delete")
            .addSection("Stroke")
            with let thickness = Slider.create(me, {})
            {
                .setValue(0.4)
            }

            discard .addRow("Thickness", thickness)
            discard .addRow("Dashes", Stepper.create(me, {}))
            .addSection("Effects")
            discard .addRow("Shadow", ToggleButton.create(me, {}), fill: false)
        }
    }

    private mtd createSheet()
    {
        with .sheet = InfoSheet.create(me)
        {
            .setTitle("panel.png")
            .setIdentity("880 × 550 · PNG · 412 KB")
            .addFact("100", "%")
            .addSection("Image")
            .addReading("Created", "2026-10-28")
            .addReading("Colors", "RGBA 8")
            .addText("A capture of the side panel, annotated for the review.")
            .addLink("Show in Folder", StageSheet)
        }
    }

    private mtd createHint()
    {
        with .hint = HintLine.create(me)
        {
            .setReading("880 × 550 · 100 %")
            .addHint(strings().key_Space, "everything else")
            .addHint("I", "sheet")
        }
    }

    // Every command of the stage is a lens entry, and the tools are found under their own family.
    private mtd createLens()
    {
        with .lens = Lens.View.create(me)
        {
            .addCommands("Stage", [StageSheet, StageInspector])
            .addCommands("Tools", [StageSelect, StageArrow, StageText])
            .addSource(.None, func(results)
            {
                const Recent = ["panel.png", "toolbar.png", "settings dialog.png"]
                var section: *Lens.Section?
                for name in Recent where Lens.match(results.query, name).matched
                {
                    if not section do
                        section = results.addSection("Recent")
                    section.addEntry(name).monoDetail = true
                }
            })
        }
    }
}
