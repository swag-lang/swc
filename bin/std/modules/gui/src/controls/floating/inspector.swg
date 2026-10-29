#global public

using Core, Pixel

// The floating property column of a selection, docked at the trailing edge of its parent.
//
// This is the inspector of the charter: the shape of the information sheet, standing
// [[Gui.ThemeMetrics.floating_Inset]] from the trailing edge, [[Gui.ThemeMetrics.inspector_Width]]
// wide. A header names the selection — a title, a faint mono detail such as "1 object", quiet
// actions at its end — and the rows below carry its properties: section labels, then rows of a
// label of [[Gui.ThemeMetrics.inspector_LabelWidth]] and an editor at the inspector height
// ([[Gui.ThemeMetrics.control_InspectorHeight]]). No border goes around an individual setting.
//
// The inspector folds to an edge tab ("Properties · I"), standing on the trailing edge with its
// words running down it, so the work takes the full width; the tab unfolds it again. The application creates the editors, hands them over with
// [[Gui.Inspector.addRow]] and keeps listening to their own signals. A selection whose settings
// are generated, such as a property grid, is handed over whole with [[Gui.Inspector.setContent]]:
// it takes the rest of the column under the rows, and the inspector then reaches down to the
// bottom inset of its parent so the content has the whole height to scroll in.
//
// ```swag
// with let inspector = Inspector.create(view)
// {
//     .setTitle("Arrow", "1 object")
//     .addSection("Stroke")
//     .addRow("Thickness", Slider.create(inspector, {}))
//     .addRow("Opacity", Slider.create(inspector, {}))
// }
// ```
struct Inspector
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        foldKey: string = "I"     // Key the application binds to fold and unfold the inspector, written on the edge tab.

        sigFoldChanged: SigArray'func||(*Inspector)     // Emitted after the inspector folds or unfolds.

        readonly
        {
            title:  String     // Name of the selection, bold at the head of the inspector.
            detail: String     // Faint mono detail beside the title, such as a count.
            folded: bool       // Whether only the edge tab shows.
        }
    }

    rows:    Array'InspectorRow
    actions: Array'(*IconButton)
    content: *Wnd?
}

// The dot written between two actions of the head of an [[Gui.Inspector]].
internal const ActionDot = "·"

// One row of an [[Gui.Inspector]]: a section label, a labelled editor, or an editor spanning the width.
internal struct InspectorRow
{
    label:  String     // Section label, or label of the editor; empty for a wide editor.
    editor: *Wnd?      // Editor of the row, or `null` for a section label.
    fill:   bool       // Whether the editor takes the width of its column rather than its own size.
    top:    f32        // Top of the row in the body, from the latest layout.
}

impl IWnd for Inspector
{
    mtd impl onLayout()
    {
        let parent = .parent
        if not parent do
            return

        let metrics = .themeMetrics()
        let bounds  = parent.clientRect()
        let inset   = metrics.floating_Inset
        let top     = bounds.y + Math.max(inset, parent.stripInset())
        liftFloating(me)

        if .folded
        {
            let tab = .tabSize()
            .setPosition(Math.Rectangle{bounds.right() - inset - tab.x, Math.round(bounds.vertCenter() - tab.y * 0.5), tab.x, tab.y})
            return
        }

        let width  = Math.min(metrics.inspector_Width, bounds.width - 2 * inset)
        let room   = Math.max(bounds.bottom() - inset - top, 0)
        let height = .content ? room : Math.min(.measureBody(), room)
        .setPosition(Math.Rectangle{bounds.right() - inset - width, top, width, height})
        .arrange(width, height)
    }

    mtd impl onBeforePaint(evt: *PaintEvent)
    {
        let metrics = .themeMetrics()
        paintFloatingShadow(me, evt.paintContext.painter, .body(), .folded ? metrics.corner_Control : metrics.corner_Floating)
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let theme   = .theme()
        let body    = .body()

        if .folded
        {
            // The words run down the tab, read with the head turned to the right, like the spine
            // of a book standing on the shelf.
            paintFloatingGround(me, painter, body, metrics.corner_Control)
            let font   = theme.createDefaultFont(metrics.defaultFontSize - 1)
            let text   = .tabText()
            let width  = Painter.measureString(text, font).width
            let center = painter.transform().transformPoint(Math.Vector2{body.horzCenter(), body.vertCenter()})
            painter.pushTransform()
            painter.rotateTransform(Math.ConstF32.Pi * 0.5, center.x, center.y)
            discard paintTextLine(painter, Math.round(body.horzCenter() - width * 0.5), body.vertCenter(), text, font, colors.softText)
            painter.popTransform()
            return
        }

        paintFloatingGround(me, painter, body, metrics.corner_Floating)

        let pad     = metrics.inspector_Padding
        let rowSize = metrics.control_InspectorHeight
        let headY   = body.y + pad + rowSize * 0.5
        if not .title.isEmpty()
        {
            let titleFont = theme.createDefaultFont(metrics.inspector_TitleFontSize, .Bold)
            let used      = paintTextLine(painter, body.x + pad, headY, .title, titleFont, colors.text)

            // The detail stops short of the actions, which keep their words whole.
            var right = body.right() - pad
            for action in .actions where action.isLocallyVisible() do
                right = Math.min(right, action.position.x - metrics.iconText_Margin)
            let left = body.x + pad + used + metrics.iconText_Margin
            painter.pushClippingRect(Math.Rectangle{left, body.y, Math.max(right - left, 0), pad + metrics.control_InspectorHeight})
            discard paintTextLine(painter, left, headY, .detail, theme.createDefaultFontFs(metrics.defaultFontSize - 2), colors.faintText)
            painter.popClippingRect()
        }

        // A middle dot between two actions of the head.
        let dotFont = theme.createDefaultFont(metrics.defaultFontSize - 1)
        for i in 1 until .actions.count
        {
            let action = .actions[i]
            if not action.isLocallyVisible() do
                continue
            let width = Painter.measureString(ActionDot, dotFont).width
            let x     = action.position.x - .actionDotWidth() * 0.5 - width * 0.5
            discard paintTextLine(painter, Math.round(x), headY, ActionDot, dotFont, colors.faintText)
        }

        painter.pushClippingRect(body)
        defer painter.popClippingRect()
        let labelFont = theme.createDefaultFont(metrics.defaultFontSize)
        for row in .rows
        {
            let top = body.y + row.top
            if not row.editor
            {
                SectionLabel.paint(me, painter, Math.Rectangle{body.x + pad, top, body.width - 2 * pad, metrics.inspector_SectionHeight}, row.label)
                continue
            }

            if not row.label.isEmpty() do
                discard paintTextLine(painter, body.x + pad, top + rowSize * 0.5, row.label, labelFont, colors.softText)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if .folded and evt.kind == .Pressed and evt.button == .Left
        {
            .setFolded(false)
            return
        }

        evt.accepted = false
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .ThemeChanged or evt.kind == .LanguageChanged do
            .itf.onLayout()
        evt.accepted = false
    }
}

impl Inspector
{
    // Creates an empty inspector floating over `parent`, unfolded.
    #[Swag.Discardable]
    func create(parent: *Wnd, id: WndId? = null)->*Inspector
    {
        with let result = Wnd.create'Inspector(parent, null, {}, id)
        {
            .dockStyle       = .Float
            .backgroundStyle = .Transparent
        }

        return result
    }

    // Names the selection: a bold `title` and an optional faint mono `detail`, such as a count.
    mtd setTitle(title: string, detail: string? = null)
    {
        .title  = title
        .detail = detail orelse ""
        .relayout()
    }

    // Appends a quiet action to the head of the inspector, such as "Duplicate", and returns it.
    //
    // The actions are small faint words after the title, a middle dot between two of them: they
    // say what can be done with the selection without standing out like buttons of a form.
    #[Swag.Discardable]
    mtd addAction(text: string, id: WndId? = null)->*IconButton
    {
        let metrics     = .themeMetrics()
        with let button = IconButton.createQuiet(me, id, menu: false)
        {
            .style.setFont(me.theme().createDefaultFont(metrics.defaultFontSize - 1), .Regular)
            .style.addStyleSheetColors("btnIcon_Text $faintText")
            .setQuietText(text)
        }

        .actions.add(button)
        .relayout()
        return button
    }

    // Appends a section label opening the rows that follow.
    mtd addSection(label: string)
    {
        .rows.add(InspectorRow{label: label})
        .relayout()
    }

    // Appends a row of `label` and `editor`, and returns the editor.
    //
    // The inspector adopts `editor` and destroys it with the row. With `fill`, the editor takes
    // the inspector height and the width of the editor column, as a field, a slider or a segment
    // group does; otherwise it keeps the size it measures, as a switch or a check box does, and
    // stands at the start of the column, centred on the row.
    #[Swag.Discardable]
    mtd addRow(label: string, editor: *Wnd, fill = true)->*Wnd
    {
        if editor.parent != me do
            editor.setParent(&.wnd)
        .rows.add(InspectorRow{label: label, editor: editor, fill: fill})
        .relayout()
        return editor
    }

    // Appends an editor spanning both columns, such as a row of alignment buttons, and returns it.
    #[Swag.Discardable]
    mtd addWideRow(editor: *Wnd)->*Wnd => .addRow("", editor)

    // Hands `content` the rest of the column under the rows, and returns it.
    //
    // The inspector adopts `content`, places it under the last row, between the paddings, down to
    // its bottom padding, and destroys it with itself; [[Gui.Inspector.clear]] keeps it. Use it for
    // settings the application generates, such as a [[Gui.Properties]] grid, which scrolls on its
    // own. The inspector then stands the whole height of its parent.
    #[Swag.Discardable]
    mtd setContent(content: *Wnd)->*Wnd
    {
        if content.parent != me do
            content.setParent(&.wnd)
        .content = content
        .relayout()
        return content
    }

    // Removes the title, the actions and every row, destroying their editors. The content set by
    // [[Gui.Inspector.setContent]] stays.
    mtd clear()
    {
        for row in .rows where row.editor do
            row.editor.destroy()
        for action in .actions do
            action.destroy()
        .rows.clear()
        .actions.clear()
        .title.clear()
        .detail.clear()
        .relayout()
    }

    // Folds the inspector to its edge tab, or unfolds it.
    mtd setFolded(folded: bool)
    {
        if .folded == folded do
            return
        .folded = folded
        for child in .children do
            child.show(not folded)
        .relayout()

        // Unfolded, the inspector arrives from its edge like any floating surface; folded, its
        // edge tab is there at once, since the hand is already on it.
        if not folded do
            discard .app().animator.arrive(me, {.themeMetrics().motion_EdgeTravel, 0})
        .sigFoldChanged.call(me)
    }

    // Folds an unfolded inspector and unfolds a folded one, as its key does.
    mtd toggleFolded() => .setFolded(not .folded)

    // Returns the height the body needs to hold the header and every row.
    mtd measureBody()->f32
    {
        let metrics = .themeMetrics()
        var y       = metrics.inspector_Padding + metrics.control_InspectorHeight + metrics.inspector_RowGap
        for &row in .rows
        {
            row.top = y
            y       += row.editor ? metrics.control_InspectorHeight + metrics.inspector_RowGap : metrics.inspector_SectionHeight
        }

        return Math.ceil(y - metrics.inspector_RowGap + metrics.inspector_Padding)
    }

    private mtd arrange(width, height: f32)
    {
        let metrics = .themeMetrics()
        let pad     = metrics.inspector_Padding
        let rowSize = metrics.control_InspectorHeight

        // The actions stand at the end of the header, the last one against the padding, a dot
        // between two of them.
        var right = width - pad
        for i in reversed(.actions.count)
        {
            let action = .actions[i]
            right -= action.position.width
            action.move(right, Math.round(pad + (rowSize - action.position.height) * 0.5))
            right -= .actionDotWidth()
        }

        let labelled = pad + metrics.inspector_LabelWidth + metrics.inspector_LabelGap
        for row in .rows where row.editor
        {
            let left = row.label.isEmpty() ? pad : labelled
            var cell = Math.Rectangle{left, row.top, width - left - pad, rowSize}
            if not row.fill
            {
                let size = row.editor.measure(Math.Point{cell.width, cell.height}).preferred
                cell.y      = Math.round(cell.vertCenter() - size.y * 0.5)
                cell.width  = Math.min(size.x, cell.width)
                cell.height = size.y
            }

            row.editor.setPosition(cell)
            row.editor.show(row.top + rowSize <= height)
        }

        if .content
        {
            let top = .rows.isEmpty() ? pad + rowSize + metrics.inspector_RowGap : .measureBody() - pad + metrics.inspector_RowGap
            .content.setPosition(Math.Rectangle{pad, top, Math.max(width - 2 * pad, 0), Math.max(height - top - pad, 0)})
        }
    }

    // The room a dot takes between two actions of the head.
    private mtd actionDotWidth()->f32
    {
        let font = .theme().createDefaultFont(.themeMetrics().defaultFontSize - 1)
        return Math.ceil(Painter.measureString(ActionDot, font).width)
    }

    private mtd body()->Math.Rectangle => .clientRect()

    private mtd tabText()->String
    {
        var result: #returntype = strings().inspector_Tab
        if .foldKey.count > 0
        {
            result.append(" · ")
            result.append(.foldKey)
        }

        return result
    }

    private mtd tabSize()->Math.Point
    {
        let metrics = .themeMetrics()
        let font    = .theme().createDefaultFont(metrics.defaultFontSize - 1)
        let length  = Painter.measureString(.tabText(), font).width + 2 * metrics.inspector_LabelGap
        return {metrics.control_InspectorHeight, Math.ceil(length)}
    }

    private mtd relayout()
    {
        .itf.onLayout()
        .invalidate()
    }
}
