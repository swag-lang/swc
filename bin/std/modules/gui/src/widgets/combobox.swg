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
    None = 0        // Always paints the field background and border.
    Flat            // Paints the field only while hovered or open.
    TransparentBackground     // Keeps the parent background visible behind the field border.
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

        minimumPopupWidth:  f32 = 100                           // Minimum drop-down width in logical units.
        maximumPopupHeight: f32 = 300                           // Maximum drop-down height in logical units.
        sigChanged:         SigArray'func||(*ComboBox, u32)     // Emitted after a notifying selection change.

        // What the combo shows. Add items through the methods, which keep the popup and the
        // measured icon width in step, and select through 'setSelected'.
        public readonly
        {
            mode          = ComboBoxMode.Selection     // Text interaction mode chosen at creation.
            flags         = ComboBoxFlags.None         // Active presentation options.
            items:   ArrayPtr'ComboBoxItem             // Entries in display order.
            selectedIndex = Swag.U32.Max               // Selected item index, or U32.Max when empty.
            editBox: #null *EditBox                    // Embedded editor in editable mode, otherwise null.
        }

        // Hover state, the open popup, and the color animations of the painted parts.
        internal
        {
            isHot:       bool                     // Whether the mouse is over the combo.
            popup:       #null *PopupListCtrl     // Drop-down list while it is open.
            maxIconSize: s32                      // Widest item icon, sizing the icon column.

            aniBk:     BlendColor     // Color animation of the background.
            aniBorder: BlendColor     // Color animation of the border.
            aniText:   BlendColor     // Color animation of the label.
        }
    }
}

impl IWnd for ComboBox
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
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

        let theme   = .theme()
        let colors  = .themeColors()
        let metrics = .themeMetrics()
        let rects   = .themeRects()

        var subRectBk:     #null *ThemeImageRect
        var subRectBorder: #null *ThemeImageRect
        var colorBk:       Color = undefined
        var colorBorder:   Color = undefined
        var colorText:     Color = undefined

        subRectBk     = &rects.edit_SquareBk
        subRectBorder = &rects.edit_SquareBorder

        .focusRingRadius = subRectBk!.radius

        switch
        {
        case bc.isDisabled:
            colorBorder = colors.comboBox_DisabledBorder
            colorBk     = colors.comboBox_DisabledBk
            colorText   = colors.comboBox_DisabledText

        case .popup != null:
            colorBorder = colors.comboBox_SelectedBorder
            colorBk     = colors.comboBox_SelectedBk
            colorText   = colors.comboBox_SelectedText

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
        if !.flags.has(.Flat) or .isHot or .popup
        {
            if !.flags.has(.TransparentBackground)
            {
                theme.drawSubRect(painter, clientRect, subRectBk, .aniBk.cur())
                .focusRingGround = .aniBk.cur()
            }
            else do
                .focusRingGround = {}
            theme.drawSubRect(painter, clientRect, subRectBorder, .aniBorder.cur())
        }
        else do
            .focusRingGround = {}

        // Item
        if !.editBox and .selectedIndex < .items.count
        {
            var format: RichStringFormat
            let item     = .items[.selectedIndex]!
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
            format.horzAlignment = .Left
            format.vertAlignment = .OpticalCenter
            format.flags         = .Clip
            format.font          = .font()
            painter.drawRichString(itemRect, &item.name, format)
        }

        // The right margin is the band the field reserves for its marker, so the marker is
        // centered in that band rather than hung off its leading edge: the glyph then keeps
        // the same air on both sides whatever size the theme gives it.
        let icon  = theme.icon(ThemeIcons.ChevronDown, metrics.chevron_Size)
        let iconX = clientRect.right() - (metrics.comboBox_RightMargin + icon.sizeX) * 0.5
        icon.paint(painter, iconX, clientRect.vertCenter() - icon.sizeY * 0.5, colorText)
    }

    // Reports the room the widest item needs beside the icon column and the drop-down arrow.
    //
    // Every item has to be readable once selected, not only the one showing now, so the
    // widest decides. The theme combo width stays a floor, which keeps a field of short
    // entries the regular size of the surface.
    mtd impl measureContent(available: Math.Point)->Math.Point
    {
        discard available

        let metrics = .themeMetrics()

        var format: RichStringFormat
        format.font = .font()

        // Measured at the density the glyphs are really drawn at, the way the label and the
        // menu bar measure theirs: a layout at a scale of one under-counts every advance,
        // and the widest entry is where that shows.
        let deviceScale = .deviceScale()

        var text = 0'f32
        for item in .items
        {
            let current = item!
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
            width += cast(f32) .maxIconSize + metrics.comboBox_IconTextMargin
        return {Math.max(width, metrics.comboBox_Width), metrics.comboBox_Height}
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
            if .popup do
                .hidePopup()
            else do
                .showPopup()

        case .Enter:
            .isHot = true
            .invalidate()

        case .Leave:
            .isHot = false
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

        let alt = cast(bool) (evt.modifiers & .Alt)

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
    // Move the selection by 'dir' (+1/-1), skipping separators and clamping at the
    // ends (no wrap-around, matching native combo boxes).
    mtd selectRelative(dir: s32)
    {
        if .items.isEmpty() do
            return

        var idx: s32
        if .selectedIndex >= .items.count do
            idx = dir > 0 ? -1 : cast(s32) .items.count
        else do
            idx = cast(s32) .selectedIndex

        for
        {
            idx += dir
            if idx < 0 or idx >= cast(s32) .items.count do
                return
            if !.items[idx]!.isSeparator do
                break
        }

        .setSelectedIndex(cast(u32) idx)
    }

    // Select the first (forward) or last (backward) non-separator item.
    mtd selectEdge(forward: bool)
    {
        if forward
        {
            for item, idx in .items
            {
                if !item!.isSeparator
                {
                    .setSelectedIndex(cast(u32) idx)
                    return
                }
            }
        }
        else
        {
            for var i = cast(s32) .items.count - 1; i >= 0; i -= 1
            {
                if !.items[i]!.isSeparator
                {
                    .setSelectedIndex(cast(u32) i)
                    return
                }
            }
        }
    }

    mtd showPopup()
    {
        let popup = PopupListCtrl.create(cast(*Wnd) me)
        .popup              = popup
        popup.minimumWidth  = .minimumPopupWidth
        popup.maximumHeight = .maximumPopupHeight
        popup.fitVertically = true

        for itemIt in .items
        {
            let item = itemIt!
            if item.isSeparator do
                popup.addSeparator()
            else do
                popup.addItem(item.name.raw, item.id, item.icon, item.userData0, item.userData1)
        }

        popup.setSelectedIndex(.selectedIndex)

        popup.sigClosed = func|combo = me|(list, idx)
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
        if !popup do
            return
        popup.destroy()
        .popup = null
    }
}

impl ComboBox
{
    // Creates a selection or editable combo box with optional presentation flags.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: #null WndId = null, mode = ComboBoxMode.Selection, flags = ComboBoxFlags.None)->*ComboBox
    {
        Debug.assert(parent != null)
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
        if result.mode == .Editable
        {
            // The field is the control's own writing surface, not a second stop beside it.
            result.editBox             = EditBox.create(result, null, {})
            result.editBox.focusPolicy = .Inner
            result.editBox.setForm(EditBoxForm.Transparent)
        }

        result.sendResizeEvent()
        return result
    }

    // Removes every item and silently clears the selection and editable text.
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
    mtd addItem(name: #null string, id: #null WndId = null, icon: Icon = {}, userData0: #null *void = null, userData1: #null *void = null)->*ComboBoxItem
    {
        let item = .items.allocate()
        with item
        {
            .name.set(name)
            .icon      = icon
            .id        = id
            .userData0 = userData0
            .userData1 = userData1
        }

        if item.icon.isValid() do
            .maxIconSize = Math.max(.maxIconSize, cast(s32) item.icon.sizeX)
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
        Debug.assert(index < .items.count)
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
    mtd const selectedItem()->#null *ComboBoxItem
    {
        if .selectedIndex >= .items.count do
            return null
        return .items[.selectedIndex]
    }

    // Opens the drop-down without moving keyboard focus away from the combo box.
    mtd openPopup()
    {
        if !.popup do
            .showPopup()
    }

    // Selects one selectable item and optionally emits the change signal and command.
    mtd setSelectedIndex(index: u32, notify = true)
    {
        Debug.assert(index < .items.count)
        Debug.assert(!.items[index]!.isSeparator)
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
            let current = item!
            if current.icon.isValid() do
                .maxIconSize = Math.max(.maxIconSize, cast(s32) current.icon.sizeX)
        }
    }
}
