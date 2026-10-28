#global public

using Core, Pixel

// Selects whether a combo box displays a selection or editable text.
enum ComboBoxMode
{
    Selection     // Displays one selected list item.
    Editable      // Embeds an editor and mirrors selected item text into it.
}

// Configures combo box presentation.
#[Swag.EnumFlags]
enum ComboBoxFlags
{
    None = 0     // Always paints the field background and border.
    Flat         // Paints the field only while hovered or open.
    TransparentBackground     // Keeps the parent background visible behind the field border.
    Segmented    // Shows every entry side by side as segments of a raised frame, chosen with a click; no list opens.
}

// Stores one selectable item or separator in a combo box.
struct ComboBoxItem
{
    public
    {
        using base:  Item     // Embedded label, icon, identifier, and user data.
        isSeparator: bool     // Whether this entry separates groups and cannot be selected.
    }
}

// Displays a compact selection field with a drop-down list.
struct ComboBox
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        minimumPopupWidth:  f32 = 100     // Minimum drop-down width in logical units.
        maximumPopupHeight: f32 = 300     // Maximum drop-down height in logical units.
        sigChanged:         SigArray'func||(*Wnd, u32)     // Emitted after a notifying selection change.

        // What the combo shows. Add items through the methods, which keep the popup and the
        // measured icon width in step, and select through [[Gui.ComboBox.setSelectedIndex]].

        readonly
        {
            mode          = ComboBoxMode.Selection     // Text interaction mode chosen at creation.
            flags         = ComboBoxFlags.None         // Active presentation options.
            items:   ArrayPtr'ComboBoxItem             // Entries in display order.
            selectedIndex = Swag.U32.Max               // Selected item index, or U32.Max when empty.
            editBox: *EditBox?     // Embedded editor in editable mode, otherwise null.
            textHorizontalAlignment = StringHorzAlignment.Left     // Horizontal alignment of selected text in selection mode.
        }
    }

    // Hover state, the open popup, and the color animations of the painted parts.
    isHot:              bool      // Whether the mouse is over the combo.
    popup:              *PopupListCtrl?     // Drop-down list while it is open.
    pointerFocusReturn: *Wnd?     // Focus owner restored after pointer use.
    maxIconSize:        s32       // Widest item icon, sizing the icon column.
    hotSegment:         u32 = Swag.U32.Max     // Segment under the pointer, when segmented.

    aniBk:     BlendColor     // Color animation of the background.
    aniBorder: BlendColor     // Color animation of the border.
    aniText:   BlendColor     // Color animation of the label.
}

impl IWnd for ComboBox
{
    mtd impl onFocusEvent(evt: *FocusEvent)
    {
        switch evt.kind
        {
        case .Gained:

            // Keyboard traversal keeps a visibly focused combo available for keyboard selection.
            // Pointer activation is transient: remember the document or control that must resume
            // receiving keys once the drop-down interaction ends.
            .pointerFocusReturn = .hasVisibleFocus() ? null : evt.other

        case .Lost:

            // A click elsewhere made an explicit focus choice; closing the popup must not undo it.
            if evt.other != .popup do
                .pointerFocusReturn = null
        }
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .editBox
        {
            let metrics    = .themeMetrics()
            var clientRect = .clientRect()
            clientRect.width -= metrics.comboBox_RightMargin
            clientRect.moveLeft(metrics.comboBox_Padding)
            .editBox.setPosition(clientRect)
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let bc      = evt.paintContext
        let painter = evt.paintContext.painter
        if .showsSegments()
        {
            .paintSegments(painter, bc.isDisabled)
            return
        }

        let theme   = .theme()
        let colors  = .themeColors()
        let metrics = .themeMetrics()
        let rects   = .themeRects()

        var subRectBk:     *ThemeImageRect?
        var subRectBorder: *ThemeImageRect?
        var colorBk:       Color
        var colorBorder:   Color
        var colorText:     Color

        subRectBk     = &rects.edit_SquareBk
        subRectBorder = &rects.edit_SquareBorder

        .focusRingRadius = subRectBk.radius

        switch
        {
        case bc.isDisabled:
            colorBorder = colors.comboBox_DisabledBorder
            colorBk     = colors.comboBox_DisabledBk
            colorText   = colors.comboBox_DisabledText

        // An open list is where the reader is acting, so the field wears the two-pixel ring of
        // what acts, exactly as a focused field does.
        case .popup != null:
            colorBorder   = colors.comboBox_SelectedBorder
            colorBk       = colors.comboBox_SelectedBk
            colorText     = colors.comboBox_SelectedText
            subRectBorder = &rects.edit_SquareStrongBorder

        case .isHot:
            colorBorder = colors.comboBox_HotBorder
            colorBk     = colors.comboBox_HotBk
            colorText   = colors.comboBox_HotText

        default:
            colorBorder = colors.comboBox_Border
            colorBk     = colors.comboBox_Bk
            colorText   = colors.comboBox_Text
        }

        .aniBk.apply(me, colorBk)
        .aniBorder.apply(me, colorBorder)
        .aniText.apply(me, colorText)

        let clientRect = .clientRect()

        // In flat (cell) mode the field is only painted while active. A transparent field keeps
        // the ground it sits on while retaining the border that identifies it as a control.
        if not .flags.has(.Flat) or .isHot or .popup
        {
            if not .flags.has(.TransparentBackground) do
                theme.drawSubRect(painter, clientRect, subRectBk, .aniBk.cur())
            theme.drawSubRect(painter, clientRect, subRectBorder, .aniBorder.cur())
        }

        // Item
        if not .editBox and .selectedIndex < .items.count
        {
            var format: RichStringFormat
            let item     = unwrap .items[.selectedIndex]
            var itemRect = clientRect
            itemRect.width -= metrics.comboBox_RightMargin
            itemRect.moveLeft(metrics.comboBox_Padding)

            // Plainly centered, like the field's own marker below: the entry beside it is
            // centered on its capitals, so both sit on the middle of the field whatever face
            // the field is set in.
            if item.icon.isValid()
            {
                let iconColor = item.icon.color.a ? item.icon.color : .aniText.cur()
                item.icon.paint(painter, itemRect.x, itemRect.vertCenter() - item.icon.sizeY * 0.5, iconColor)
            }

            if .maxIconSize do
                itemRect.moveLeft(.maxIconSize + metrics.comboBox_IconTextMargin)

            theme.setTextColors(&format, .aniText.cur())
            format.horzAlignment = .textHorizontalAlignment
            format.vertAlignment = .OpticalCenter
            format.flags         = .Clip
            format.font          = .font()
            painter.drawRichString(itemRect, &item.name, format)
        }

        // The right margin is the band the field reserves for its marker, so the marker is
        // centered in that band rather than hung off its leading edge: the glyph then keeps
        // the same air on both sides whatever size the theme gives it.
        // The marker only says a list opens: faint at rest, in the ink of the words once the
        // pointer or the open list engages the field.
        let icon      = theme.icon(ThemeIcons.ChevronDown, metrics.chevron_Size)
        let iconX     = clientRect.right() - (metrics.comboBox_RightMargin + icon.sizeX) * 0.5
        let iconColor = bc.isDisabled or .isHot or .popup ? colorText : colors.faintText
        icon.paint(painter, iconX, clientRect.vertCenter() - icon.sizeY * 0.5, iconColor)
    }

    // Reports the room the widest item needs beside the icon column and the drop-down arrow.
    //
    // Every item has to be readable once selected, not only the one showing now, so the
    // widest decides. The theme combo width stays a floor, which keeps a field of short
    // entries the regular size of the surface.
    mtd impl measureContent(_: Math.Point)->Math.Point
    {
        let metrics = .themeMetrics()
        if .flags.has(.Segmented)
        {
            var width = 0'f32
            for item in .items where not item!.isSeparator do
                width += Painter.measureString(item.name.raw, unwrap .font().regular).width + 2 * metrics.comboBox_Padding
            return Math.Point{width, metrics.comboBox_Height}
        }

        var format: RichStringFormat
        format.font = .font()

        // Measured at the density the glyphs are really drawn at, the way the label and the
        // menu bar measure theirs: a layout at a scale of one under-counts every advance,
        // and the widest entry is where that shows.
        let deviceScale = .deviceScale()

        var text = 0'f32
        for item in .items
        {
            let current = unwrap item
            if current.isSeparator do
                continue
            current.name.compute()
            Painter.computeLayout({0, 0, MaxTextLayoutExtent, MaxTextLayoutExtent}, &current.name, format, deviceScale)
            text = Math.max(text, current.name.boundRect.width)
        }

        // The right margin is the room the drop-down arrow is painted in, so the field
        // padding is counted again before it: without that the widest entry would read as
        // touching the arrow.
        var width = 2 * metrics.comboBox_Padding + text + metrics.comboBox_RightMargin
        if .maxIconSize do
            width += cast(f32, .maxIconSize) + metrics.comboBox_IconTextMargin
        return Math.Point{Math.max(width, metrics.comboBox_Width), metrics.comboBox_Height}
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        switch evt.kind
        {
        case .Wheel:
            evt.accepted = false
            return

        case .Pressed:
            if evt.button != .Left do
                break
            if .showsSegments()
            {
                let index = .segmentAt(.surfaceToLocal(evt.surfacePos))
                if index < .items.count and index != .selectedIndex do
                    .applySelectedIndex(index, notify: true)
                break
            }

            if .popup do
                .hidePopup()
            else do
                .showPopup()

        case .Move:
            if .showsSegments()
            {
                let index = .segmentAt(.surfaceToLocal(evt.surfacePos))
                if index != .hotSegment
                {
                    .hotSegment = index
                    .invalidate()
                }
            }

        case .Enter:
            .isHot = true
            .invalidate()

        case .Leave:
            .isHot      = false
            .hotSegment = Swag.U32.Max
            .invalidate()
        }
    }

    // Keyboard control of the focused combo box. Up/Left and Down/Right move the
    // selection to the previous/next selectable item; Home/End jump to the first/
    // last; Enter/Space (or Alt+Down) open the drop-down and Escape closes it.
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .Pressed do
            return

        let alt = evt.modifiers.has(.Alt)

        // When the drop-down is open, the keys drive the list selection.
        if .popup
        {
            switch evt.key
            {
            case .Up:             .popup.moveHighlight(-1)
            case .Down:           .popup.moveHighlight(1)
            case .Home:           .popup.highlightFirst()
            case .End:            .popup.highlightLast()
            case .Return, .Space: .popup.commitHighlighted()
            case .Escape:         .popup.cancel()
            default:              return
            }

            evt.accepted = true
            return
        }

        // Segments are all on screen: the keys move the choice, nothing opens.
        if .showsSegments()
        {
            switch evt.key
            {
            case .Up, .Left:    .selectRelative(-1)
            case .Down, .Right: .selectRelative(1)
            case .Home:         .selectEdge(forward: true)
            case .End:          .selectEdge(forward: false)
            default:            return
            }

            evt.accepted = true
            return
        }

        switch evt.key
        {
        case .Down where alt: .showPopup()
        case .Return, .Space: .showPopup()
        case .Up, .Left:      .selectRelative(-1)
        case .Down, .Right:   .selectRelative(1)
        case .Home:           .selectEdge(forward: true)
        case .End:            .selectEdge(forward: false)
        default:              return
        }

        evt.accepted = true
    }
}

private impl ComboBox
{
    // Reports whether the entries stand as segments: the combo asks for it and every entry fits
    // its share of the width. A choice whose words do not fit stays a list that opens.
    mtd showsSegments()->bool
    {
        if not .flags.has(.Segmented) or .items.isEmpty() do
            return false
        let metrics = .themeMetrics()
        let font    = unwrap .font().regular
        let share   = (.clientRect().width - 2 * metrics.comboBox_SegmentInset) / cast(f32, .items.count)
        for item in .items
        {
            if item!.isSeparator or Painter.measureString(item.name.raw, font).width + 2 * metrics.comboBox_Padding > share do
                return false
        }

        return true
    }

    // Returns the rectangle of segment `index` among `count`, in local coordinates: the frame
    // shares its width evenly, inset by the gap the chosen segment keeps from the frame.
    mtd segmentRect(index, count: u64)->Math.Rectangle
    {
        let gap   = .themeMetrics().comboBox_SegmentInset
        var frame = .clientRect()
        frame.inflate(-gap)
        let width = frame.width / cast(f32, Math.max(count, 1))
        return Math.Rectangle{frame.x + width * cast(f32, index), frame.y, width, frame.height}
    }

    // Returns the segment under `pos`, in local coordinates, or `U32.Max`.
    mtd segmentAt(pos: Math.Point)->u32
    {
        let count = .items.count
        for i in count where .segmentRect(i, count).contains(pos) do
            return cast(u32, i)
        return Swag.U32.Max
    }

    // Paints the entries as segments: a raised frame, the chosen segment on its own ground,
    // lifted where the theme lifts it, the others in the soft ink.
    mtd paintSegments(painter: *Painter, disabled: bool)
    {
        let colors = .themeColors()
        let rects  = .themeRects()
        let theme  = .theme()
        let count  = .items.count
        let font   = unwrap .font().regular

        theme.drawSubRect(painter, .clientRect(), &rects.tabBar_RoundBk, colors.tabBar_RoundBk)
        painter.setParams(.Antialiased)
        for item, i in .items
        {
            let rect = .segmentRect(i, count)
            if i == .selectedIndex
            {
                let lift = colors.tabItem_RoundLift
                if lift.a
                {
                    var shade = rect
                    shade.offset(0, 1)
                    painter.fillRoundRect(shade, rects.tabItem_RoundSelected.radius, rects.tabItem_RoundSelected.radius, lift)
                }

                theme.drawSubRect(painter, rect, &rects.tabItem_RoundSelected, colors.tabItem_RoundSelected)
            }
            elif i == .hotSegment
            {
                theme.drawSubRect(painter, rect, &rects.tabItem_RoundSelected, colors.tabItem_ButtonHot)
            }

            var ink = i == .selectedIndex ? colors.tabItem_SelectedText : colors.tabItem_HotText
            if disabled do
                ink = colors.comboBox_DisabledText
            let text  = item!.name.raw
            let width = Painter.measureString(text, font).width
            painter.drawString(Math.round(rect.horzCenter() - width * 0.5), font.opticalLineTop(rect.vertCenter()), text, font, ink)
        }
    }

    // Move the selection by 'dir' (+1/-1), skipping separators and clamping at the
    // ends (no wrap-around, matching native combo boxes).
    mtd selectRelative(dir: s32)
    {
        if .items.isEmpty() do
            return

        var idx: s32
        if .selectedIndex >= .items.count do
            idx = dir > 0 ? -1 : cast(s32, .items.count)
        else do
            idx = cast(s32, .selectedIndex)

        for
        {
            idx += dir
            if idx < 0 or idx >= cast(s32, .items.count) do
                return
            if not .items[idx]!.isSeparator do
                break
        }

        .setSelectedIndex(cast(u32, idx))
    }

    // Select the first (forward) or last (backward) non-separator item.
    mtd selectEdge(forward: bool)
    {
        if forward
        {
            for item, idx in .items
            {
                if not item!.isSeparator
                {
                    .setSelectedIndex(cast(u32, idx))
                    return
                }
            }
        }
        else
        {
            for var i = cast(s32, .items.count) - 1; i >= 0; i -= 1
            {
                if not .items[i]!.isSeparator
                {
                    .setSelectedIndex(cast(u32, i))
                    return
                }
            }
        }
    }

    mtd showPopup()
    {
        let popup = PopupListCtrl.create(cast(*Wnd, me))
        .popup = popup
        popup.minimumWidth  = .minimumPopupWidth
        popup.maximumHeight = .maximumPopupHeight
        popup.fitVertically = true

        for itemIt in .items
        {
            let item = unwrap itemIt
            if item.isSeparator do
                popup.addSeparator()
            else do
                popup.addItem(item.name.raw, item.id, item.icon, item.userData0, item.userData1)
        }

        popup.setSelectedIndex(.selectedIndex)

        popup.sigClosed = func|combo = me|(_, idx)
        {
            if idx != Swag.U32.Max do
                combo.setSelectedIndex(idx)
            combo.hidePopup()
        }

        let rect = .surfaceRect()
        popup.show(rect.x, rect.bottom(), rect.width)
    }

    mtd hidePopup()
    {
        let popup = .popup
        if not popup do
            return

        let restoreFocus = .hasFocus() and not .hasVisibleFocus() ? .pointerFocusReturn : null
        .popup = null
        popup.destroy()
        .pointerFocusReturn = null

        // Pointer-opened command lists are temporary overlays. Once dismissed they return the
        // keyboard to its previous owner instead of leaving an invisible focus on the field.
        if restoreFocus and
           not restoreFocus.isPendingDestroy and
           restoreFocus.surface == .surface and
           restoreFocus.isEnabled() do
            restoreFocus.setFocus()
    }
}

impl ComboBox
{
    // Aligns the selected text within the space between the icon column and the drop-down arrow.
    //
    // This affects selection mode only; editable text and popup entries keep their own layout.
    mtd setTextAlignment(horizontal: StringHorzAlignment)
    {
        if .textHorizontalAlignment == horizontal do
            return
        .textHorizontalAlignment = horizontal
        .invalidate()
    }

    // Creates a selection or editable combo box with optional presentation flags.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: WndId? = null, mode = ComboBoxMode.Selection, flags = ComboBoxFlags.None)->*ComboBox
    {
        Swag.assert(parent != null)
        let metrics = parent.themeMetrics()

        // The theme height is a floor, not a default. A field packed below it clips its own
        // wording and stops matching the fields it stands beside, and a caller asking for a
        // shorter row is really asking for a shorter row, not for a broken control.
        var pos = position
        pos.height = Math.max(pos.height, metrics.comboBox_Height)
        if pos.width == 0 do
            pos.width = metrics.comboBox_Width
        let result = Wnd.create'ComboBox(parent, null, pos, id)

        result.mode        = mode
        result.flags       = flags
        result.focusPolicy = .Tab
        result.minSize.y   = metrics.comboBox_Height

        // An unstated width belongs to the items: the theme width above only gives the
        // field a sane size until the first layout pass measures it, and stays its floor.
        if position.width == 0 do
            result.preferredSize.x = 0
        else do
            result.minSize.x = pos.width
        if result.mode == .Editable
        {
            // The field is the control's own writing surface, not a second stop beside it.
            result.editBox = EditBox.create(result, null, {})
            result.editBox.focusPolicy = .Inner
            result.editBox.setForm(EditBoxForm.Transparent)
        }

        result.sendResizeEvent()
        return result
    }

    // Removes every item and clears the selection without emitting [[Gui.ComboBox.sigChanged]].
    //
    // An editable combo box that had a selection also clears the text it mirrored from it.
    mtd clear()
    {
        .hidePopup()
        .maxIconSize = 0
        .items.clear()
        .applySelectedIndex(Swag.U32.Max, notify: false)
        .invalidate()
    }

    // Appends a selectable item and returns its stable heap object.
    #[Swag.Discardable]
    mtd addItem(name: string?, id: WndId? = null, icon: Icon = {}, userData0: *void? = null, userData1: *void? = null)->*ComboBoxItem
    {
        with let item = .items.allocate()
        {
            .name.set(name)
            .icon      = icon
            .id        = id
            .userData0 = userData0
            .userData1 = userData1
        }

        if item.icon.isValid() do
            .maxIconSize = Math.max(.maxIconSize, cast(s32, item.icon.sizeX))
        .items.add(item)
        .hidePopup()
        .invalidate()
        return item
    }

    // Appends a non-selectable separator and returns its stable heap object.
    #[Swag.Discardable]
    mtd addSeparator()->*ComboBoxItem
    {
        let item = .items.allocate()
        item.isSeparator = true
        .items.add(item)
        .hidePopup()
        .invalidate()
        return item
    }

    // Removes one item while preserving order and adjusts the selection silently.
    mtd removeItemAt(index: u32)
    {
        Swag.assert(index < .items.count)
        .hidePopup()
        .items.deleteAt(index)
        .recomputeMaximumIconWidth()

        if .selectedIndex == index do
            .applySelectedIndex(Swag.U32.Max, notify: false)
        elif .selectedIndex > index and .selectedIndex != Swag.U32.Max do
            .selectedIndex -= 1
        .invalidate()
    }

    // Returns the selected item, or null when the combo box has no selection.
    mtd const selectedItem()->*ComboBoxItem?
    {
        if .selectedIndex >= .items.count do
            return null
        return .items[.selectedIndex]
    }

    // Opens the drop-down without moving keyboard focus away from the combo box.
    mtd openPopup()
    {
        if not .popup do
            .showPopup()
    }

    // Selects one selectable item and optionally emits the change signal and command.
    mtd setSelectedIndex(index: u32, notify = true)
    {
        Swag.assert(index < .items.count)
        Swag.assert(not .items[index]!.isSeparator)
        .applySelectedIndex(index, notify)
    }

    // Removes the current selection and optionally emits the change signal.
    mtd clearSelection(notify = true)
    {
        .applySelectedIndex(Swag.U32.Max, notify)
    }

    // Adds and removes presentation options, then repaints the combo box.
    mtd updateFlags(add: ComboBoxFlags = .None, remove = ComboBoxFlags.None)
    {
        .flags.add(add)
        .flags.remove(remove)
        .invalidate()
    }
}

private impl ComboBox
{
    mtd applySelectedIndex(index: u32, notify: bool)
    {
        if index == .selectedIndex do
            return

        .selectedIndex = index
        let editBox = .editBox
        if editBox
        {
            if .selectedIndex < .items.count do
                editBox.setText(.items[.selectedIndex]!.name.raw)
            else do
                editBox.setText("")
        }

        if notify
        {
            .sigChanged.call(me, .selectedIndex)
            if .selectedIndex < .items.count do
                .postCommandEvent(.items[.selectedIndex]!.id)
        }

        .invalidate()
    }

    mtd recomputeMaximumIconWidth()
    {
        .maxIconSize = 0
        for item in .items
        {
            let current = unwrap item
            if current.icon.isValid() do
                .maxIconSize = Math.max(.maxIconSize, cast(s32, current.icon.sizeX))
        }
    }
}
