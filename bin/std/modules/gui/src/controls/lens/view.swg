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
// Opened with nothing typed, the lens is a palette of what can be done here and now, not a list
// of everything: the sections of the rest sources ([[Gui.Lens.View.addRestSource]]) — the actions
// of the object in hand — then the commands chosen last. An application that declares neither
// still lists all its commands at rest. Typed into, the sources answer first, in their own order,
// as they know their rows best; the families of commands follow, ranked by their best command,
// each from the best answer down, and commands matched only by scattered letters are left out
// when others answer better.
//
// Applications open the lens with `Ctrl Space` by calling [[Gui.Lens.View.open]].
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

            chosenPicture: u64     // Picture of the chosen strip the keys stand on; past its pictures, its link.
        }
    }

    late input:   *EditBox
    commands:     Array'Command
    sources:      Array'Source
    restSources:  Array'Provider     // What the lens offers before anything is typed.
    recent:       Array'String       // Commands chosen last, the latest first.
    sectionOrder: Array'u64          // Sections in the order they show, by index into the results.
    scroll:       f32
    returnFocus:  *Wnd?
    hotPicture:   PictureHit
    segment:      u64     // Segment the keys chose in the chosen row of an inline section, by index into its entries.
}

// A picture of a strip of the lens under a point: the row of the strip, and the picture, or the
// count of pictures of the section for its link.
internal struct PictureHit
{
    row:   u64 = Swag.U64.Max
    index: u64
}

// The `entry` of the [[Gui.Lens.Row]] holding the strip of pictures of its section.
const PictureRow = Swag.U64.Max - 1

// The `entry` of the [[Gui.Lens.Row]] holding every row of an inline section, as segments.
const InlineRow = Swag.U64.Max - 2

// The ring of the picture the keys stand on, in a strip of the lens: its gap and its weight.
internal const PictureRingGap   = 2.0
internal const PictureRingWidth = 2.0

// One line of the results of a [[Gui.Lens.View]]: the label of a section, one of its rows, or its strip of pictures.
struct Row
{
    public
    {
        section: *Section     // Section the line belongs to.
        entry:   u64          // Index of the row in its section, `U64.Max` for the section label, [[Gui.Lens.PictureRow]] for the strip, [[Gui.Lens.InlineRow]] for the segments.
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
            elif row.entry == PictureRow do
                .paintPictureRow(painter, rect, row.section)
            elif row.entry == InlineRow do
                .paintInlineRow(painter, rect, row.section, index == .chosen)
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

            // In a row of segments, the pointer chooses the segment under it.
            let row = .rowAt(pos)
            if row != Swag.U64.Max and (evt.delta.x != 0 or evt.delta.y != 0)
            {
                let inline  = .rows[row].entry == InlineRow
                let segment = inline ? .segmentAt(row, pos.x) : 0
                if not (inline and segment == Swag.U64.Max) and (row != .chosen or (inline and segment != .segment))
                {
                    .chosen = row
                    if inline do
                        .segment = segment
                    .invalidate()
                }
            }

            // A picture under the pointer is ringed, and the keys go on from it.
            let hot = .pictureAt(pos)
            if hot.row != .hotPicture.row or hot.index != .hotPicture.index
            {
                .hotPicture = hot
                if hot.row != Swag.U64.Max
                {
                    .chosen        = hot.row
                    .chosenPicture = hot.index
                }

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

            // A picture or the link of a strip runs at once.
            let picture = .pictureAt(pos)
            if picture.row != Swag.U64.Max
            {
                let section = .rows[picture.row].section
                let run     = picture.index < section.pictures.count ? section.pictures[picture.index].run : section.linkRun
                .close()
                if run do
                    run()
                break
            }

            let row = .rowAt(pos)
            if row != Swag.U64.Max
            {
                if .rows[row].entry == InlineRow
                {
                    let segment = .segmentAt(row, pos.x)
                    if segment == Swag.U64.Max do
                        break
                    .segment = segment
                }

                .chosen = row
                .runChosen()
            }

        case .Wheel:
            .scrollBy(-evt.delta.y * .themeMetrics().lens_RowHeight)
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = evt.kind == .Pressed and .handleKey(evt.key, evt.modifiers)
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

// Returns the top of a lens opened over `over`, from the top of `over`: near its top third, and
// clear of the window chrome.
private func restingTop(over: *Wnd, height: f32)->f32
{
    let metrics = over.themeMetrics()
    return Math.max(Math.round(height * metrics.lens_TopRatio), over.stripInset() + metrics.floating_Inset)
}

// Returns where a box `width` wide, opened by a command chosen in a lens over `over`, stands:
// centred where the lens stood, its top on the top of the lens, in surface coordinates.
//
// A command chosen in the lens may ask for more, a zoom or an option sheet. Its box takes the
// place the reader's eyes were on, not the corner of a control the window does not show.
func followUpPoint(over: *Wnd, width: f32)->Math.Point
{
    let rect = over.surfaceRect()
    return {Math.round(rect.horzCenter() - width * 0.5), rect.y + restingTop(over, rect.height)}
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
                    if lens.handleKey(key.key, key.modifiers)
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

    // Registers a source of the rows the lens offers before anything is typed.
    //
    // A rest source adds the sections of what can be done here and now — the actions of the
    // selection, of the open file, of the stage — and reads the state of the application each time
    // the lens opens. They show in the order they were added, before the commands chosen last.
    mtd addRestSource(provide: Provider)
    {
        .restSources.add(provide)
    }

    // Adds to `section` the rows of the commands `ids`, as the owner of the lens states them now.
    //
    // A hidden command is left out, and with `enabledOnly` one that cannot run now as well. This
    // is how a rest source offers the actions of the object in hand: a selection's commands are
    // registered once, and only those that apply show.
    mtd addCommandRows(section: *Section, ids: const [..] WndId, enabledOnly = false)
    {
        let found = .ownerOrParent()
        if not found do
            return
        let owner: *Wnd = found
        for id in ids
        {
            let state = owner.sendComputeCommandStateEvent(id)
            if state.updatedFields.has(.Hidden) and state.hidden do
                continue
            if enabledOnly and state.updatedFields.has(.Disabled) and state.disabled do
                continue
            var title: String
            if state.updatedFields.has(.LongName) do
                title = state.longName
            elif state.updatedFields.has(.Name) do
                title = state.name
            if title.isEmpty() do
                continue

            with let entry = section.addEntry(title)
            {
                .id         = id
                .disabled   = state.updatedFields.has(.Disabled) and state.disabled
                .checked    = state.updatedFields.has(.Checked) and state.checked
                .checkable  = state.updatedFields.has(.Checked)
                .monoDetail = true
                if state.updatedFields.has(.Icon) do
                    .glyph = state.icon
                if state.updatedFields.has(.Shortcut) do
                    .detail = state.shortcut

                // A row that cannot run says why instead of the key that would run it.
                if .disabled and state.updatedFields.has(.Reason)
                {
                    .detail     = state.reason
                    .monoDetail = false
                }
            }
        }
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

        // At rest the lens is a palette of the context and the commands chosen last; an
        // application that declares neither lists everything, as typing an empty query would.
        if typed.count == 0 and (not .restSources.isEmpty() or not .recent.isEmpty())
        {
            for provide in .restSources do
                provide(&.results)
            .addRecentSection()
        }
        else
        {
            for source in .sources where split.prefix == .None or source.prefix == split.prefix do
                source.provide(&.results)

            if split.prefix == .None or split.prefix == .Action do
                .addCommandSections()
        }

        // A source that marked nothing leaves the marking to the lens; a row the query does not
        // answer, shown for its group, is not marked.
        for section in .results.sections
        {
            for &entry in section!.entries where entry.spans.isEmpty() and .results.query.count > 0
            {
                var found = match(.results.query, entry.title)
                if found.matched do
                    entry.spans = #move found.spans
            }
        }

        .rankResults()
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
            .chosen        = cast(u64, last)
            .chosenPicture = 0
            let row = .rows[.chosen]
            if row.entry == InlineRow do
                .segment = .restingSegment(row.section)
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
        if row.entry == InlineRow do
            return .segment < row.section.entries.count ? &row.section.entries[.segment] : null
        if row.entry == PictureRow do
            return null
        return &row.section.entries[row.entry]
    }

    // Returns the strip of pictures the keys stand on, or null.
    mtd chosenStrip()->*Section?
    {
        if .chosen >= .rows.count or .rows[.chosen].entry != PictureRow do
            return null
        return .rows[.chosen].section
    }

    // Closes the lens and runs the chosen row, as Enter does.
    //
    // Nothing runs when no row is chosen or the chosen row is disabled. With `keepOpen`, as
    // `Ctrl Enter` asks, the lens stays, its rows are asked for again so a setting shows its new
    // state, and the choice stays on the row that ran.
    mtd runChosen(keepOpen = false)
    {
        // A picture of a strip, or its link, runs as a click does.
        let strip = .chosenStrip()
        if strip
        {
            let run = .chosenPicture < strip.pictures.count ? strip.pictures[.chosenPicture].run : strip.linkRun
            .close()
            if run do
                run()
            return
        }

        let entry = .chosenEntry()
        if not entry or entry.disabled do
            return

        let run   = entry.run
        let id    = entry.id
        let owner = .ownerOrParent()
        if id do
            .remember(id)

        if not keepOpen
        {
            .close()
            if run do
                run()
            elif id and owner do
                owner.postCommandEvent(id)
            return
        }

        if run do
            run()
        elif id and owner do
            owner.sendCommandEvent(id)

        let chosen  = .chosen
        let segment = .segment
        .refresh()
        if chosen < .rows.count and .isSelectable(chosen)
        {
            .chosen  = chosen
            .segment = segment
            .revealChosen()
            .invalidate()
        }
    }
}

private impl View
{
    // The keys of the lens, whichever of its windows holds the keyboard. `Ctrl Enter` runs the
    // chosen row and keeps the lens open, to flip several settings in a row.
    mtd handleKey(key: Input.Key, modifiers: Input.KeyModifiers)->bool
    {
        if key == .Return and modifiers == .Control
        {
            .runChosen(keepOpen: true)
            return true
        }

        let page = Math.max(1's64, cast(s64, .listRect().height / .themeMetrics().lens_RowHeight) - 1)

        // Along a strip of pictures, the arrows go from one picture to the next, then to its link.
        let strip = .chosenStrip()
        if strip and (key == .Left or key == .Right)
        {
            let count = strip.pictures.count + (strip.link.isEmpty() ? 0 : 1)
            if key == .Left and .chosenPicture > 0 do
                .chosenPicture -= 1
            elif key == .Right and .chosenPicture + 1 < count do
                .chosenPicture += 1
            .invalidate()
            return true
        }

        switch key
        {
        case .Up:       .moveChoice(-1)
        case .Down:     .moveChoice(1)
        case .PageUp:   .moveChoice(-page)
        case .PageDown: .moveChoice(page)
        case .Return:   .runChosen()
        case .Escape:   .backOut()
        case .Left:     return .moveSegment(-1)
        case .Right:    return .moveSegment(1)
        default:        return false
        }

        return true
    }

    // Moves the chosen segment of a row of segments by one, staying on the first or the last one.
    // Reports false when the chosen row is not one, and the key belongs to the query.
    mtd moveSegment(delta: s64)->bool
    {
        if .chosen >= .rows.count or .rows[.chosen].entry != InlineRow do
            return false
        let section = .rows[.chosen].section
        var at      = 0's64
        for i, pos in section.order where i == .segment do
            at = cast(s64, pos)

        var index = at + delta
        while index >= 0 and index < cast(s64, section.order.count)
        {
            let entry = section.order[cast(u64, index)]
            if not section.entries[entry].disabled
            {
                .segment = entry
                .invalidate()
                break
            }

            index += delta
        }

        return true
    }

    // Returns the segment the keys land on when they reach the row of `section`: the one the query
    // answers best, else the one in force, else the first that can be chosen.
    mtd restingSegment(section: *Section)->u64
    {
        var result = Swag.U64.Max
        var best   = Swag.S64.Min
        for i in section.order where not section.entries[i].disabled
        {
            let entry = &section.entries[i]
            var score = cast(s64, entry.score) * 2
            if entry.checked do
                score += 1
            if result == Swag.U64.Max or score > best
            {
                result = i
                best   = score
            }
        }

        return result
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

                if not section
                {
                    section        = .results.addSection(family[])
                    section.ranked = true
                }

                addCommandEntry(section, command.id, title, state)
            }
        }
    }

    // Lays the sections out as one column of lines under the input.
    mtd buildRows()
    {
        let metrics = .themeMetrics()
        .rows.clear()

        // The sections in the order the ranking gave them; the strips of pictures close the
        // results, after every row a key can reach.
        var order: Array'(*Section)
        for s in .sectionOrder
        {
            let section = unwrap .results.sections[s]
            if section.pictures.isEmpty() do
                order.add(section)
        }

        for section in .results.sections where not section!.pictures.isEmpty() do
            order.add(section)

        var y = metrics.lens_RowInset
        for section in order
        {
            if section.order.isEmpty() and section.pictures.isEmpty() do
                continue
            .rows.add(Row{section, Swag.U64.Max, y, metrics.lens_SectionHeight})
            y += metrics.lens_SectionHeight
            if section.inline and not section.order.isEmpty()
            {
                .rows.add(Row{section, InlineRow, y, metrics.lens_RowHeight})
                y += metrics.lens_RowHeight
            }

            for i in section.order where not section.inline
            {
                .rows.add(Row{section, i, y, metrics.lens_RowHeight})
                y += metrics.lens_RowHeight
            }

            if not section.pictures.isEmpty()
            {
                let height = metrics.lens_PictureHeight + 2 * metrics.lens_PictureGap
                .rows.add(Row{section, PictureRow, y, height})
                y += height
            }
        }
    }

    mtd isSelectable(index: u64)->bool
    {
        let row = .rows[index]
        if row.entry == InlineRow
        {
            for i in row.section.order where not row.section.entries[i].disabled do
                return true
            return false
        }

        if row.entry == PictureRow do
            return not row.section.pictures.isEmpty()
        return row.entry != Swag.U64.Max and not row.section.entries[row.entry].disabled
    }

    // Returns the cell of picture `index` of a strip whose row stands at `rect`; `index` past the
    // pictures is the link.
    mtd pictureRect(rect: Math.Rectangle, section: *Section, index: u64)->Math.Rectangle
    {
        let metrics = .themeMetrics()
        let x       = rect.x + metrics.lens_TextInset + cast(f32, index) * (metrics.lens_PictureWidth + metrics.lens_PictureGap)
        let y       = rect.y + metrics.lens_PictureGap
        if index < section.pictures.count do
            return {x, y, metrics.lens_PictureWidth, metrics.lens_PictureHeight}

        let font  = .theme().createDefaultFont(metrics.defaultFontSize)
        let width = Painter.measureString(section.link, font).width
        return {x, y, width, metrics.lens_PictureHeight}
    }

    // Returns the cell of the segment `entry` of the inline `section` whose row stands at `rect`.
    mtd segmentRect(rect: Math.Rectangle, section: *Section, entry: u64)->Math.Rectangle
    {
        let metrics = .themeMetrics()
        let font    = .theme().createDefaultFont(metrics.lens_RowFontSize)
        let top     = Math.round(rect.vertCenter() - metrics.lens_SegmentHeight * 0.5)
        var x       = rect.x + metrics.lens_TextInset
        for i in section.order
        {
            let width = Math.round(Painter.measureString(section.entries[i].title, font).width + 2 * metrics.lens_SegmentInset)
            if i == entry do
                return {x, top, width, metrics.lens_SegmentHeight}
            x += width
        }

        return {x, top, 0, 0}
    }

    // Returns the segment of the inline row `rowIndex` under the abscissa `x`, by index into the
    // entries of its section, or `U64.Max` when none can be chosen there.
    mtd segmentAt(rowIndex: u64, x: f32)->u64
    {
        let list    = .listRect()
        let row     = .rows[rowIndex]
        let rect    = Math.Rectangle{list.x, list.y + row.top - .scroll, list.width, row.height}
        let section = row.section
        for i in section.order
        {
            let cell = .segmentRect(rect, section, i)
            if x >= cell.x and x < cell.right() do
                return section.entries[i].disabled ? Swag.U64.Max : i
        }

        return Swag.U64.Max
    }

    // Returns the picture, or the link, of a strip under `pos`.
    mtd pictureAt(pos: Math.Point)->PictureHit
    {
        var none: PictureHit
        let list = .listRect()
        if not list.contains(pos) do
            return none
        for row, rowIndex in .rows where row.entry == PictureRow
        {
            let rect  = Math.Rectangle{list.x, list.y + row.top - .scroll, list.width, row.height}
            let count = row.section.pictures.count + (row.section.link.isEmpty() ? 0 : 1)
            for i in count where .pictureRect(rect, row.section, i).contains(pos) do
                return PictureHit{row: rowIndex, index: i}
        }

        return none
    }

    mtd contentHeight()->f32
    {
        let metrics = .themeMetrics()
        if .rows.isEmpty() do
            return .results.query.count > 0 ? metrics.lens_RowHeight + 2 * metrics.lens_RowInset : 0
        let last = .rows.back()
        return last.top + last.height + metrics.lens_RowInset
    }

    // Returns the height of the results shown in at most `room`: all of them, or the rows that
    // fit whole, so that the list never ends on half a row or on a section label alone.
    //
    // The air under a row is not part of what it shows: a row that only loses some of it stays.
    mtd fittedContentHeight(room: f32)->f32
    {
        let whole = .contentHeight()
        if whole <= room do
            return whole

        let inset  = .themeMetrics().lens_RowInset
        var result = 0'f32
        for row in .rows
        {
            let bottom = row.top + row.height
            if bottom > room + inset do
                break
            if row.entry != Swag.U64.Max do
                result = bottom
        }

        return result > 0 ? Math.min(result, room) : room
    }

    // The visible lens, in local coordinates.
    mtd body()->Math.Rectangle
    {
        let parent  = .parent
        let metrics = .themeMetrics()
        let bounds  = .clientRect()
        let inset   = metrics.floating_Inset
        let width   = Math.min(metrics.lens_Width, bounds.width - 2 * inset)
        let top     = parent ? restingTop(parent, bounds.height) : inset
        let fixed   = metrics.lens_InputHeight + metrics.lens_FooterHeight + 2 * metrics.separator_HairlineSize
        let room    = Math.max(Math.min(bounds.height * metrics.lens_MaxHeightRatio, bounds.height - inset - top), fixed)
        let height  = fixed + .fittedContentHeight(room - fixed)
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

    // Paints the strip of pictures of `section`, then its link in the Arc ink.
    mtd paintPictureRow(painter: *Painter, rect: Math.Rectangle, section: *Section)
    {
        let strip   = .chosenStrip()
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let radius  = metrics.corner_Chip
        painter.setParams(.Antialiased)
        for &picture, i in section.pictures
        {
            let cell = .pictureRect(rect, section, i)
            if cell.x > rect.right() do
                break
            painter.pushClippingRect(cell)
            painter.fillRect(cell, colors.raised)
            if picture.paint do
                picture.paint(painter, cell)
            painter.popClippingRect()

            // The picture the keys stand on is ringed in Arc, the one under the pointer too.
            let chosen = strip == section and .chosenPicture == i
            let hot    = .hotPicture.index == i and
                         .hotPicture.row < .rows.count and
                         .rows[.hotPicture.row].section == section
            if chosen
            {
                var ring = cell
                ring.inflate(PictureRingGap + PictureRingWidth * 0.5)
                painter.drawRoundRect(ring, radius + PictureRingGap, radius + PictureRingGap, colors.arc, PictureRingWidth)
            }

            painter.drawRoundRect(cell, radius, radius, hot ? colors.arc : colors.line, hot ? 1.5 : metrics.separator_HairlineSize)
        }

        if not section.link.isEmpty()
        {
            let cell = .pictureRect(rect, section, section.pictures.count)
            let font = .theme().createDefaultFont(metrics.defaultFontSize)
            if strip == section and .chosenPicture == section.pictures.count
            {
                var ground = cell
                ground.inflate(metrics.lens_PictureGap * 0.5, metrics.lens_PictureGap)
                painter.fillRoundRect(ground, metrics.corner_Control, metrics.corner_Control, colors.selection)
            }

            discard paintTextLine(painter, cell.x, cell.vertCenter(), section.link, font, colors.arc)
        }
    }

    // Paints the rows of an inline `section` as segments side by side: the one in force
    // underlined in Arc, and the one the keys chose on the selection ground when the row is chosen.
    mtd paintInlineRow(painter: *Painter, rect: Math.Rectangle, section: *Section, chosen: bool)
    {
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let theme   = .theme()
        let font    = theme.createDefaultFont(metrics.lens_RowFontSize)
        painter.setParams(.Antialiased)
        for i in section.order
        {
            let entry = &section.entries[i]
            let cell  = .segmentRect(rect, section, i)
            if chosen and i == .segment do
                painter.fillRoundRect(cell, metrics.corner_Control, metrics.corner_Control, colors.selection)

            // The characters the query matched, on the highlight ground.
            let left = cell.x + metrics.lens_SegmentInset
            let top  = font.opticalLineTop(cell.vertCenter())
            let mark = entry.disabled ? fadeColor(colors.highlight, 0.4) : colors.highlight
            for span in entry.spans where span.start + span.count <= entry.title.length
            {
                let before = Painter.measureString(Swag.makeString(entry.title.buffer, span.start), font).width
                let after  = Painter.measureString(Swag.makeString(entry.title.buffer, span.start + span.count), font).width
                painter.fillRect(Math.Rectangle{Math.round(left + before), top, Math.round(after - before), font.height}, mark)
            }

            var ink = (entry.checked or (chosen and i == .segment)) ? colors.text : colors.softText
            if entry.disabled do
                ink = colors.disabled
            painter.drawString(left, top, entry.title, font, ink)
            if entry.checked
            {
                let width = Painter.measureString(entry.title, font).width
                painter.fillRect(Math.Rectangle{left, top + font.height + 2, Math.round(width), 2}, entry.disabled ? colors.disabled : colors.arc)
            }
        }

        // The key that runs the chosen segment, at the end of the row, where a chosen row has it.
        if chosen
        {
            let small = theme.createDefaultFont(metrics.defaultFontSize - 1)
            let enter = "↵"
            let right = rect.right() - metrics.lens_TextInset
            discard paintTextLine(painter, right - Painter.measureString(enter, small).width, rect.vertCenter(), enter, small, colors.faintText)
        }
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

        // A row that cannot be chosen keeps its matches, faded with its words.
        let top  = font.opticalLineTop(centerY)
        let mark = entry.disabled ? fadeColor(colors.highlight, 0.4) : colors.highlight
        for span in entry.spans where span.start + span.count <= entry.title.length
        {
            let before = Painter.measureString(Swag.makeString(entry.title.buffer, span.start), font).width
            let after  = Painter.measureString(Swag.makeString(entry.title.buffer, span.start + span.count), font).width
            painter.fillRect(Math.Rectangle{Math.round(titleLeft + before), top, Math.round(after - before), font.height}, mark)
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
        x += paintKeycap(me, painter, x, centerY, strings().key_Enter) + metrics.hintLine_KeyGap
        x += paintTextLine(painter, x, centerY, strings().lens_Go, font, colors.faintText) + metrics.hintLine_GroupGap

        // A setting or a choice can be run without leaving the lens.
        if .chosenIsCheckable()
        {
            x += paintKeycap(me, painter, x, centerY, strings().key_CtrlEnter) + metrics.hintLine_KeyGap
            discard paintTextLine(painter, x, centerY, strings().lens_Stay, font, colors.faintText)
        }

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

    // Reports whether the chosen row is a setting or a choice: one marked checkable, or a segment
    // of a row of segments, which are the choices of one setting.
    mtd chosenIsCheckable()->bool
    {
        let entry = .chosenEntry()
        if not entry or entry.disabled do
            return false
        return entry.checkable or .rows[.chosen].entry == InlineRow
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

// How many commands chosen last the lens offers at rest.
private const RecentCount = 5

// Adds the row of the command `id`, titled `title`, in the state `state` its owner computed.
private func addCommandEntry(section: *Section, id: WndId, title: string, state: const *CommandStateEvent)
{
    with let entry = section.addEntry(title)
    {
        .id         = id
        .disabled   = state.updatedFields.has(.Disabled) and state.disabled
        .checked    = state.updatedFields.has(.Checked) and state.checked
        .checkable  = state.updatedFields.has(.Checked)
        .monoDetail = true
        if state.updatedFields.has(.Icon) do
            .glyph = state.icon
        if state.updatedFields.has(.Shortcut) do
            .detail = state.shortcut

        // A row that cannot run says why instead of the key that would run it.
        if .disabled and state.updatedFields.has(.Reason)
        {
            .detail     = state.reason
            .monoDetail = false
        }
    }
}

private impl View
{
    // Keeps `id` first among the commands chosen last.
    mtd remember(id: WndId)
    {
        let text: string = id
        for i in .recent.count where .recent[i] == text
        {
            .recent.removeAtOrdered(i)
            break
        }

        .recent.insertAt(0, String.from(text))
        if .recent.count > RecentCount do
            .recent.removeBack()
    }

    // Adds the commands chosen last, as their owner states them now.
    mtd addRecentSection()
    {
        let owner = .ownerOrParent()
        if not owner or .recent.isEmpty() do
            return

        var section: *Section?
        for text in .recent
        {
            for command in .commands where text[] == command.id
            {
                let state = owner.sendComputeCommandStateEvent(command.id)
                if state.updatedFields.has(.Hidden) and state.hidden do
                    break
                var title: String
                if state.updatedFields.has(.LongName) do
                    title = state.longName
                elif state.updatedFields.has(.Name) do
                    title = state.name
                if title.isEmpty() do
                    break

                if not section do
                    section = .results.addSection(strings().lens_Recent)
                addCommandEntry(section, command.id, title, &state)
                break
            }
        }
    }

    // Ranks the rows of the query on screen. The sections of the sources keep their order and
    // their rows; the families of commands follow, ranked by their best command, each from the
    // best answer down. When a command answers better than scattered letters, the commands that
    // only answer with scattered letters are left out.
    mtd rankResults()
    {
        let query   = .results.query.toString()
        var bestAll = Swag.S32.Min
        for section in .results.sections
        {
            for &entry in section!.entries
            {
                if query.count == 0
                {
                    entry.score = 0
                    continue
                }

                var found = match(query, entry.title)
                entry.score = found.matched ? found.score : 0
                if entry.spans.isEmpty() and found.matched do
                    entry.spans = #move found.spans
                if section.ranked do
                    bestAll = Math.max(bestAll, entry.score)
            }
        }

        let leaveScattered = query.count >= 2 and bestAll >= ClearMatchScore
        var sectionKeys: Array'u64
        for section, index in .results.sections
        {
            let sec = unwrap section
            sec.order.clear()
            sec.best = Swag.S32.Min
            var keys: Array'u64
            let ranks = sec.ranked and query.count != 0
            for entry, i in sec.entries
            {
                if ranks and leaveScattered and entry.score < ClearMatchScore do
                    continue
                sec.best = Math.max(sec.best, entry.score)
                keys.add(ranks ? rankKey(entry.score, i) : i)
            }

            keys.sort()
            for key in keys do
                sec.order.add(key & 0xFFFFFFFF)
            if not sec.order.isEmpty() do
                sectionKeys.add(ranks ? (1'u64 << 63) | rankKey(sec.best, index) : index)
        }

        // The sources first, in their order; then the families of commands, best first.
        sectionKeys.sort()
        .sectionOrder.clear()
        for key in sectionKeys do
            .sectionOrder.add(key & 0xFFFFFFFF)
    }

    // Empties the query, or closes the lens when nothing is typed.
    mtd backOut()
    {
        if .input.text().count != 0
        {
            .setQuery("")
            return
        }

        .close()
    }
}

// Returns a key sorting a higher `score` first, and equal scores in the order of `index`.
private func rankKey(score: s32, index: u64)->u64
{
    let rank = cast(u64, (MaxRankScore - Math.clamp(score, 0, MaxRankScore)))
    return (rank << 32) | index
}

// Highest score a key distinguishes; every score of the matcher stays under it.
private const MaxRankScore = 1000000's32
