#global public
#global namespace Lens

using Core, Pixel

// The one door of an application: a floating input that finds and runs everything.
//
// This is the lens of the charter. It opens near the top third of its window, at most
// [[Gui.ThemeMetrics.lens_Width]] wide, on the surface ground with the floating corner and shadow,
// and dims the work behind it. A 64 px input takes the query; the results stand under it grouped
// under section labels, one row per entry with its glyph or number, the characters the query
// matched highlighted, and the chosen row on the Arc selection ground. The keys are listed at its
// foot. `↑` `↓` choose, Enter runs the chosen row, `Esc` or a click outside closes it.
//
// An application feeds it two ways:
//
// - **Commands** — [[Gui.Lens.View.addCommand]] registers a command identifier under a family
//   label, such as "File". The lens reads its label, glyph, shortcut and state from the owner's
//   command routing each time it opens, exactly as a menu does, and posts the command when it is
//   chosen. Every command of an application is registered, so every command can be found.
// - **Sources** — [[Gui.Lens.View.addSource]] registers a [[Gui.Lens.Provider]] that answers a
//   query with sections of its own: the lines of a document, its symbols, files to open, recent
//   captures. A source answers the unprefixed query and the one of its [[Gui.Lens.Prefix]];
//   commands answer the unprefixed query and `>`.
//
// The application opens the lens from the key it chooses — `Space`, or `Ctrl K` where Space
// types text — by calling [[Gui.Lens.View.open]].
//
// ```swag
// with let lens = Lens.View.create(mainWnd)
// {
//     .addCommands(func()->string => appStrings().lens_File, [ActionFile.Open, ActionFile.Save])
//     .addSource(.Line, func|doc|(results)
//     {
//         let section = results.addSection("In this file")
//         for line, index in doc.lines where Lens.match(results.query, line).matched
//         {
//             with let entry = section.addEntry(line)
//             {
//                 .lead      = Format.toString("%", index + 1)
//                 .monoTitle = true
//             }
//         }
//     })
// }
//
// mainWnd.registerKeyShortcut(.Control, .K, "app.lens")    // and call lens.open() on that command
// ```
struct View
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        readonly
        {
            results: Results       // Answer to the query on screen.
            chosen:  u64 = Swag.U64.Max     // Row the keys and the pointer chose, among `rows`, or `U64.Max`.
            rows:    Array'Row     // Section labels and entries, in the order they show.
        }
    }

    late input:  *EditBox
    commands:    Array'Command
    sources:     Array'Source
    scroll:      f32
    returnFocus: *Wnd?
}

// One line of the results of a [[Gui.Lens.View]]: the label of a section, or one of its rows.
struct Row
{
    public
    {
        section: *Section     // Section the line belongs to.
        entry:   u64          // Index of the row in its section, or `U64.Max` for the section label.
        top:     f32          // Top of the line under the input, before scrolling.
        height:  f32          // Height of the line.
    }
}

// A command registered on a [[Gui.Lens.View]].
internal struct Command
{
    id:         WndId = ""
    family:     String
    familyText: MenuLabelResolver?
}

// A source registered on a [[Gui.Lens.View]].
internal struct Source
{
    prefix:  Prefix
    provide: Provider
}

impl IWnd for View
{
    mtd impl onLayout()
    {
        let parent = .parent
        if not parent do
            return
        .setPosition(parent.clientRect())
        .placeInput()
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let body    = .body()

        painter.fillRect(.clientRect(), colors.lens_Dim)
        paintFloatingShadow(me, painter, body, metrics.corner_Floating)
        paintFloatingGround(me, painter, body, metrics.corner_Floating)

        // The input band: the query is the edit box; the faint name of the key that closes the
        // lens stands at its end.
        let small  = .theme().createDefaultFont(metrics.defaultFontSize)
        let escKey = strings().key_Escape
        let escX   = body.right() - metrics.lens_TextInset - Painter.measureString(escKey, small).width
        discard paintTextLine(painter, escX, body.y + metrics.lens_InputHeight * 0.5, escKey, small, colors.faintText)
        painter.fillRect(Math.Rectangle{body.x, body.y + metrics.lens_InputHeight, body.width, metrics.separator_HairlineSize}, colors.line)

        let list = .listRect()
        painter.pushClippingRect(list)
        if .rows.isEmpty() and .results.query.count > 0
        {
            discard paintTextLine(painter, body.x + metrics.lens_TextInset, list.y + metrics.lens_RowHeight * 0.5, strings().lens_Empty, small, colors.faintText)
        }

        for row, index in .rows
        {
            let rect = Math.Rectangle{body.x, list.y + row.top - .scroll, body.width, row.height}
            if rect.bottom() < list.y or rect.y > list.bottom() do
                continue
            if row.entry == Swag.U64.Max do
                .paintSectionRow(painter, rect, row.section)
            else do
                .paintEntryRow(painter, rect, &row.section.entries[row.entry], index == .chosen)
        }

        painter.popClippingRect()
        .paintFooter(painter, body)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let pos = .surfaceToLocal(evt.surfacePos)
        switch evt.kind
        {
        case .Move:
            let row = .rowAt(pos)
            if row != Swag.U64.Max and row != .chosen and (evt.delta.x != 0 or evt.delta.y != 0)
            {
                .chosen = row
                .invalidate()
            }

        case .Pressed:
            if evt.button != .Left do
                break
            if not .body().contains(pos)
            {
                .close()
                break
            }

            let row = .rowAt(pos)
            if row != Swag.U64.Max
            {
                .chosen = row
                .runChosen()
            }

        case .Wheel:
            .scrollBy(-evt.delta.y * .themeMetrics().lens_RowHeight)
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = evt.kind == .Pressed and .handleKey(evt.key)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if (evt.kind == .ThemeChanged or evt.kind == .LanguageChanged) and .isLocallyVisible()
        {
            .input.setPlaceholder(strings().lens_Placeholder)
            .input.style.setFont(.theme().createDefaultFontFamily(.themeMetrics().lens_InputFontSize))
            .refresh()
        }

        evt.accepted = false
    }
}

impl View
{
    // Creates a hidden lens over the top view of `owner`.
    //
    // `owner` routes the commands of the lens: their labels, glyphs and states are computed from
    // it, and a chosen command is posted to it.
    #[Swag.Discardable]
    func create(owner: *Wnd)->*View
    {
        with let result = Wnd.create'View(owner.topView(), null, {})
        {
            .owner           = owner
            .dockStyle       = .Float
            .backgroundStyle = .Transparent
            .focusPolicy     = .Click
            .wndFlags.add(.Hidden)
        }

        let metrics = result.themeMetrics()
        with result.input = EditBox.create(result, "", {})
        {
            .setForm(.Transparent)
            .wndFlags.add(.NoFocusRing)
            .setPlaceholder(strings().lens_Placeholder)
            .style.setFont(result.theme().createDefaultFontFamily(metrics.lens_InputFontSize))
            .sigTextChanged += func|lens = result|(_)
            {
                lens.refresh()
            }

            .hookOnEvent = func|lens = result|(wnd, evt)->bool
            {
                if evt is KeyEvent as key where key.kind == .Pressed
                {
                    if lens.handleKey(key.key)
                    {
                        key.accepted = true
                        return true
                    }

                    // Typing belongs to the query: a key without a command modifier never
                    // reaches the shortcuts of the window behind the lens.
                    if not key.modifiers.has(.Control) and not key.modifiers.has(.Alt)
                    {
                        wnd.itf.onEvent(evt)
                        key.accepted = true
                        return true
                    }
                }

                return false
            }
        }

        return result
    }

    // Registers the command `id` under the section label `family`.
    //
    // The row shows the label, glyph and shortcut the owner computes for the command, and is left
    // out while the command is hidden. A disabled command shows faint and cannot be chosen.
    mtd addCommand(family: string, id: WndId)
    {
        .commands.add(Command{id: id, family: family})
    }

    // Registers the command `id` under a section label read from `family` each time the lens
    // opens, so it follows the language of the application.
    mtd addCommand(family: MenuLabelResolver, id: WndId)
    {
        .commands.add(Command{id: id, familyText: family})
    }

    // Registers several commands under the section label `family`.
    mtd addCommands(family: string, ids: const [..] WndId)
    {
        for id in ids do
            .addCommand(family, id)
    }

    // Registers several commands under a section label read from `family` each time the lens opens.
    mtd addCommands(family: MenuLabelResolver, ids: const [..] WndId)
    {
        for id in ids do
            .addCommand(family, id)
    }

    // Registers a source of rows answering the unprefixed query and the query of `prefix`.
    //
    // With [[Gui.Lens.Prefix.None]], the source answers the unprefixed query only. Sources answer
    // in the order they were added, before the commands.
    mtd addSource(prefix: Prefix, provide: Provider)
    {
        .sources.add(Source{prefix, provide})
    }

    // Opens the lens with `query` typed in its input, such as a prefix.
    //
    // The keyboard moves to the input and comes back where it was when the lens closes.
    mtd open(query: string = "")
    {
        .returnFocus = .focusedWindow()
        .itf.onLayout()
        .bringToFront()
        discard .app().animator.arrive(me)
        .input.setText(query, notify: false)
        .input.setSelection(query.count, query.count)
        .input.setFocus()
        .refresh()
    }

    // Closes the lens without running anything.
    mtd close()
    {
        if not .isLocallyVisible() do
            return
        discard .app().animator.leave(me)
        let back = .returnFocus
        .returnFocus = null
        if back and not back.isPendingDestroy and back.isVisible() do
            back.setFocus()
    }

    // Reports whether the lens is on screen.
    mtd isOpen()->bool => .isLocallyVisible()

    // Replaces the query, as if the reader typed it.
    mtd setQuery(query: string)
    {
        .input.setText(query, notify: false)
        .refresh()
    }

    // Returns the query typed in the input, prefix included.
    mtd query()->string => .input.text()

    // Asks every source and command for the rows of the query on screen again.
    mtd refresh()
    {
        let typed = .input.text()
        let split = splitPrefix(typed)
        .results.reset(split.rest, split.prefix)

        for source in .sources where split.prefix == .None or source.prefix == split.prefix do
            source.provide(&.results)

        if split.prefix == .None or split.prefix == .Action do
            .addCommandSections()

        // A source that marked nothing leaves the marking to the lens.
        for section in .results.sections
        {
            for &entry in section!.entries where entry.spans.isEmpty() and .results.query.count > 0
            {
                var found = match(.results.query, entry.title)
                entry.spans = #move found.spans
            }
        }

        .buildRows()
        .scroll = 0
        .chosen = Swag.U64.Max
        .moveChoice(1)
        .itf.onLayout()
        .invalidate()
    }

    // Moves the choice by `delta` selectable rows, staying on the first or the last one.
    mtd moveChoice(delta: s64)
    {
        var index = .chosen == Swag.U64.Max ? -1's64 : cast(s64, .chosen)
        var steps = Math.abs(delta)
        let step  = delta < 0 ? -1's64 : 1's64
        var last  = index
        while steps > 0
        {
            index += step
            if index < 0 or index >= cast(s64, .rows.count) do
                break
            if .isSelectable(cast(u64, index))
            {
                last  = index
                steps -= 1
            }
        }

        if last >= 0 and cast(u64, last) != .chosen
        {
            .chosen = cast(u64, last)
            .revealChosen()
            .invalidate()
        }
    }

    // Returns the chosen row, or `null` when nothing is chosen.
    mtd chosenEntry()->*Entry?
    {
        if .chosen >= .rows.count do
            return null
        let row = .rows[.chosen]
        return &row.section.entries[row.entry]
    }

    // Closes the lens and runs the chosen row, as Enter does.
    //
    // Nothing runs when no row is chosen or the chosen row is disabled.
    mtd runChosen()
    {
        let entry = .chosenEntry()
        if not entry or entry.disabled do
            return

        let run   = entry.run
        let id    = entry.id
        let owner = .ownerOrParent()
        .close()
        if run do
            run()
        elif id and owner do
            owner.postCommandEvent(id)
    }
}

private impl View
{
    // The keys of the lens, whichever of its windows holds the keyboard.
    mtd handleKey(key: Input.Key)->bool
    {
        let page = Math.max(1's64, cast(s64, .listRect().height / .themeMetrics().lens_RowHeight) - 1)
        switch key
        {
        case .Up:       .moveChoice(-1)
        case .Down:     .moveChoice(1)
        case .PageUp:   .moveChoice(-page)
        case .PageDown: .moveChoice(page)
        case .Return:   .runChosen()
        case .Escape:   .close()
        default:        return false
        }

        return true
    }

    // Groups the matching commands by family, in the order they were registered.
    mtd addCommandSections()
    {
        let owner = .ownerOrParent()
        if not owner do
            return

        var families: Array'String
        for &command in .commands
        {
            if command.familyText do
                command.family = command.familyText()
            if not families.contains(command.family) do
                families.add(command.family)
        }

        for family in families
        {
            var section: *Section?
            for command in .commands where command.family == family[]
            {
                let state = owner.sendComputeCommandStateEvent(command.id)
                if state.updatedFields.has(.Hidden) and state.hidden do
                    continue

                var title: String
                if state.updatedFields.has(.LongName) do
                    title = state.longName
                elif state.updatedFields.has(.Name) do
                    title = state.name
                if title.isEmpty() do
                    continue

                let found = match(.results.query, title)
                if not found.matched do
                    continue

                if not section do
                    section = .results.addSection(family[])
                with let entry = section.addEntry(title)
                {
                    .id         = command.id
                    .disabled   = state.updatedFields.has(.Disabled) and state.disabled
                    .checked    = state.updatedFields.has(.Checked) and state.checked
                    .monoDetail = true
                    if state.updatedFields.has(.Icon) do
                        .glyph = state.icon
                    if state.updatedFields.has(.Shortcut) do
                        .detail = state.shortcut
                }
            }
        }
    }

    // Lays the sections out as one column of lines under the input.
    mtd buildRows()
    {
        let metrics = .themeMetrics()
        .rows.clear()
        var y = metrics.lens_RowInset
        for section in .results.sections where not section!.entries.isEmpty()
        {
            .rows.add(Row{section, Swag.U64.Max, y, metrics.lens_SectionHeight})
            y += metrics.lens_SectionHeight
            for i in section.entries.count
            {
                .rows.add(Row{section, i, y, metrics.lens_RowHeight})
                y += metrics.lens_RowHeight
            }
        }
    }

    mtd isSelectable(index: u64)->bool
    {
        let row = .rows[index]
        return row.entry != Swag.U64.Max and not row.section.entries[row.entry].disabled
    }

    mtd contentHeight()->f32
    {
        let metrics = .themeMetrics()
        if .rows.isEmpty() do
            return .results.query.count > 0 ? metrics.lens_RowHeight + 2 * metrics.lens_RowInset : 0
        let last = .rows.back()
        return last.top + last.height + metrics.lens_RowInset
    }

    // The visible lens, in local coordinates.
    mtd body()->Math.Rectangle
    {
        let parent  = .parent
        let metrics = .themeMetrics()
        let bounds  = .clientRect()
        let inset   = metrics.floating_Inset
        let width   = Math.min(metrics.lens_Width, bounds.width - 2 * inset)
        let strip   = parent ? parent.stripInset() : 0
        let top     = Math.max(Math.round(bounds.height * metrics.lens_TopRatio), strip + inset)
        let fixed   = metrics.lens_InputHeight + metrics.lens_FooterHeight + 2 * metrics.separator_HairlineSize
        let room    = Math.max(Math.min(bounds.height * metrics.lens_MaxHeightRatio, bounds.height - inset - top), fixed)
        let height  = Math.min(fixed + .contentHeight(), room)
        return {Math.round(bounds.horzCenter() - width * 0.5), top, width, height}
    }

    // The results, between the input band and the footer.
    mtd listRect()->Math.Rectangle
    {
        let metrics = .themeMetrics()
        let body    = .body()
        let top     = body.y + metrics.lens_InputHeight + metrics.separator_HairlineSize
        let bottom  = body.bottom() - metrics.lens_FooterHeight - metrics.separator_HairlineSize
        return {body.x, top, body.width, Math.max(bottom - top, 0)}
    }

    mtd placeInput()
    {
        let metrics = .themeMetrics()
        let body    = .body()
        let escape  = Painter.measureString(strings().key_Escape, .theme().createDefaultFont(metrics.defaultFontSize)).width
        let room    = body.width - 2 * metrics.lens_TextInset - escape - metrics.hintLine_GroupGap
        .input.setPosition(Math.Rectangle{body.x + metrics.lens_TextInset, body.y, room, metrics.lens_InputHeight})
    }

    mtd rowAt(pos: Math.Point)->u64
    {
        let list = .listRect()
        if not list.contains(pos) do
            return Swag.U64.Max
        let y = pos.y - list.y + .scroll
        for row, index in .rows where y >= row.top and y < row.top + row.height and .isSelectable(index) do
            return index
        return Swag.U64.Max
    }

    mtd scrollBy(delta: f32)
    {
        let list = .listRect()
        .scroll = Math.clamp(.scroll + delta, 0, Math.max(.contentHeight() - list.height, 0))
        .invalidate()
    }

    mtd revealChosen()
    {
        if .chosen >= .rows.count do
            return
        let list = .listRect()
        let row  = .rows[.chosen]

        // The label of a section stays in view with its first row.
        var top = row.top
        if .chosen > 0 and .rows[.chosen - 1].entry == Swag.U64.Max do
            top = .rows[.chosen - 1].top
        if top < .scroll do
            .scroll = top - .themeMetrics().lens_RowInset
        elif row.top + row.height > .scroll + list.height do
            .scroll = row.top + row.height - list.height + .themeMetrics().lens_RowInset
        .scroll = Math.clamp(.scroll, 0, Math.max(.contentHeight() - list.height, 0))
    }

    mtd paintSectionRow(painter: *Painter, rect: Math.Rectangle, section: *Section)
    {
        let metrics       = .themeMetrics()
        var label: String = section.label
        if section.count > 0 do
            label.append(Format.toString(" · %", section.count))

        // The label sits low in its band, closer to the rows it opens than to the group above.
        let band = Math.Rectangle{rect.x + metrics.lens_TextInset, rect.y + rect.height - metrics.lens_RowHeight * 0.6, rect.width - 2 * metrics.lens_TextInset, metrics.lens_RowHeight * 0.4}
        SectionLabel.paint(me, painter, band, label)
    }

    mtd paintEntryRow(painter: *Painter, rect: Math.Rectangle, entry: *Entry, chosen: bool)
    {
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let theme   = .theme()
        let centerY = rect.vertCenter()

        var ground = rect
        ground.x     += metrics.lens_RowInset
        ground.width -= 2 * metrics.lens_RowInset
        if chosen
        {
            painter.setParams(.Antialiased)
            painter.fillRoundRect(ground, metrics.corner_Control, metrics.corner_Control, colors.selection)
        }

        let inkText  = entry.disabled ? colors.disabled : colors.text
        let leadLeft = rect.x + metrics.lens_TextInset
        let mono     = theme.createDefaultFontFs(metrics.lens_RowFontSize - 1)
        if not entry.lead.isEmpty()
        {
            let width = Painter.measureString(entry.lead, mono).width
            discard paintTextLine(painter, leadLeft + metrics.lens_LeadWidth - metrics.iconText_Margin - width, centerY, entry.lead, mono, colors.faintText)
        }
        elif entry.glyph.isValid()
        {
            let size = metrics.menuPopup_IconSize
            var icon = entry.glyph
            icon.sizeX, icon.sizeY = size
            icon.paint(painter, leadLeft + (metrics.lens_LeadWidth - metrics.iconText_Margin - size) * 0.5, Math.round(centerY - size * 0.5), entry.disabled ? colors.disabled : colors.softText)
        }

        // The end of the row: the faint reading, and the key that runs the chosen row.
        let small    = theme.createDefaultFont(metrics.defaultFontSize - 1)
        var trailing = ground.right() - metrics.lens_TextInset + metrics.lens_RowInset
        if chosen
        {
            let enter = "↵"
            trailing -= Painter.measureString(enter, small).width
            discard paintTextLine(painter, trailing, centerY, enter, small, colors.faintText)
            trailing -= metrics.hintLine_GroupGap
        }

        // A choice in force carries its check in Arc, at the end of the row.
        if entry.checked
        {
            let check = "✓"
            trailing -= Painter.measureString(check, small).width
            discard paintTextLine(painter, trailing, centerY, check, small, entry.disabled ? colors.disabled : colors.arc)
            trailing -= metrics.hintLine_GroupGap
        }

        if not entry.detail.isEmpty()
        {
            let font = entry.monoDetail ? theme.createDefaultFontFs(metrics.defaultFontSize - 2) : small
            trailing -= Painter.measureString(entry.detail, font).width
            discard paintTextLine(painter, trailing, centerY, entry.detail, font, colors.faintText)
            trailing -= metrics.hintLine_GroupGap
        }

        // The title, with the characters the query matched on the highlight ground.
        let titleLeft = leadLeft + metrics.lens_LeadWidth
        let font      = entry.monoTitle ? theme.createDefaultFontFs(metrics.lens_RowFontSize - 1) : theme.createDefaultFont(metrics.lens_RowFontSize)
        painter.pushClippingRect(Math.Rectangle{titleLeft, rect.y, Math.max(trailing - titleLeft, 0), rect.height})
        let top = font.opticalLineTop(centerY)
        for span in entry.spans where span.start + span.count <= entry.title.length
        {
            let before = Painter.measureString(Swag.makeString(entry.title.buffer, span.start), font).width
            let after  = Painter.measureString(Swag.makeString(entry.title.buffer, span.start + span.count), font).width
            painter.fillRect(Math.Rectangle{Math.round(titleLeft + before), top, Math.round(after - before), font.height}, colors.highlight)
        }

        painter.drawString(titleLeft, top, entry.title, font, inkText)
        painter.popClippingRect()
    }

    mtd paintFooter(painter: *Painter, body: Math.Rectangle)
    {
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let font    = .theme().createDefaultFont(metrics.hintLine_FontSize)
        let top     = body.bottom() - metrics.lens_FooterHeight
        let centerY = top + metrics.lens_FooterHeight * 0.5
        painter.fillRect(Math.Rectangle{body.x, top - metrics.separator_HairlineSize, body.width, metrics.separator_HairlineSize}, colors.line)

        var x = body.x + metrics.lens_TextInset
        x += paintKeycap(me, painter, x, centerY, "↑↓") + metrics.hintLine_KeyGap
        x += paintTextLine(painter, x, centerY, strings().lens_Choose, font, colors.faintText) + metrics.hintLine_GroupGap
        x += paintKeycap(me, painter, x, centerY, "↵") + metrics.hintLine_KeyGap
        discard paintTextLine(painter, x, centerY, strings().lens_Go, font, colors.faintText)

        // The prefixes this lens answers, from the trailing edge.
        const Prefixes = [Prefix.Action, Prefix.File, Prefix.Line]
        var right = body.right() - metrics.lens_TextInset
        for prefix in Prefixes where .answers(prefix)
        {
            let words = prefixWords(prefix)
            right -= Painter.measureString(words, font).width
            discard paintTextLine(painter, right, centerY, words, font, colors.faintText)
            right -= metrics.hintLine_KeyGap + keycapWidth(me, prefixText(prefix))
            discard paintKeycap(me, painter, right, centerY, prefixText(prefix))
            right -= metrics.hintLine_GroupGap
        }
    }

    // Reports whether a source, or the commands for `>`, answers the queries of `prefix`.
    mtd answers(prefix: Prefix)->bool
    {
        if prefix == .Action and not .commands.isEmpty() do
            return true
        for source in .sources where source.prefix == prefix do
            return true
        return false
    }
}

// Returns what the queries of `prefix` look for, as the foot of the lens words it.
private func prefixWords(prefix: Prefix)->string
{
    switch prefix
    {
    case .Line: return strings().lens_Line
    case .File: return strings().lens_Files
    default:    return strings().lens_Actions
    }
}
