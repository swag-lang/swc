using Core, Pixel

// Selects how a popup menu is positioned around its anchor point.
public enum PopupPosition
{
    TopLeft                // Places the popup's top-left corner at the anchor.
    TopRight               // Places the popup's top-right corner at the anchor, for a menu opened from the end of a line.
    AnchorTopCenter        // Centers the popup below the anchor.
    AnchorBottomCenter     // Centers the popup above the anchor.
}

// Selects the side on which a popup menu opens its child menus.
public enum SubmenuDirection
{
    Automatic     // Opens right when it fits, otherwise left.
    Left          // Opens child menus on the left and points their markers left.
    Right         // Opens child menus on the right and points their markers right.
}

// Configures menu presentation.
#[Swag.EnumFlags]
public enum MenuFlags
{
    None = 0          // Shows command shortcut labels.
    HideShortcuts     // Hides command shortcut labels.
}

// Answers the label of a menu item every time the menu computes its layout.
//
// An item built from a literal keeps the wording it was built with, because the string is
// copied into the item once. An item built from a resolver reads its label again on every
// layout, the way an item driven by a command identifier already does, which is what lets a
// menu bar follow a language switch.
public alias MenuLabelResolver = func()->string

// Stores one command, submenu, or separator in a [[Gui.MenuCtrl]].
public struct PopupMenuItem
{
    public
    {
        using item: Item           // Embedded label, icon, identifier, and user data.
        rightName:  RichString     // Optional right-aligned shortcut label.

        // Re-reads 'name' on every layout, or `null` when the label was set once.
        nameResolver: MenuLabelResolver?

        late popup: *MenuCtrl     // Child menu this item opens, for a submenu item.
        pos:        f32           // Leading edge along the menu axis, set by the layout pass.
        size:       f32           // Extent along the menu axis, set by the layout pass.
        rg:         CommandStateEvent.RenderingHint     // Rendering hint, such as membership of an exclusive group.
        separator:  bool          // Whether the item is a separator.
        label:      bool          // Whether the item is the label opening a group of a popup, never chosen.
        disabled:   bool          // Whether the item cannot be chosen.
        checked:    bool          // Whether the item shows a check or radio mark.
        hidden:     bool          // Whether the item is left out of the menu.
        critical:   bool          // Whether the item destroys something: its words take the critical ink.
    }

    submenuOpensLeft: bool     // Resolved opening side used by layout and painting.
}

// Displays either a persistent menu bar or a modal popup menu.
public struct MenuCtrl
{
    public
    {
        using frameWnd: FrameWnd     // Embedded frame behavior and presentation.

        sigCommandSelected: SigArray'func||(*Wnd, WndId)           // Emitted after a command is selected.
        onPrepareItem:      (func(*MenuCtrl, *PopupMenuItem))?     // Updates an item before menu layout is computed.

        readonly
        {
            flags: MenuFlags = None           // Active presentation options.
            submenuDirection: SubmenuDirection = SubmenuDirection.Automatic     // Preferred side for child menus.
            items: ArrayPtr'PopupMenuItem     // Commands, submenus, and separators in display order.
        }
    }

    paddingSel:              f32 = 4                // Selection-background padding.
    hotIdx:                  u32 = Swag.U32.Max     // Item currently under the pointer.
    selectedIdx:             u32 = Swag.U32.Max     // Item selected by keyboard navigation.
    bar:                     bool                   // Whether this control is a persistent menu bar.
    endModal:                bool                   // Whether the active modal loop should end.
    endModalResult:          WndId?                 // Selected command, or `null` when dismissed.
    ownerMenu:               *MenuCtrl?             // Parent menu for a submenu.
    subVisible:              *MenuCtrl?             // Currently visible submenu.
    timer:                   *Timer?                // Delayed submenu-opening timer.
    dirtyLayout:             bool                   // Whether item bounds need recomputing.
    paintByFrame:            bool                   // Whether the frame paints an anchored popup.
    popupBarItemIdx:         u32 = Swag.U32.Max     // Owning menu-bar item for an anchored popup.
    popupBarItemSurfaceRect: Math.Rectangle         // Owning menu-bar item bounds in surface coordinates.
    popupAnchorButton:       *IconButton?           // Icon button repainted as the tab of an attached popup.
    popupButtonOpensUp:      bool                   // Whether an attached icon-button menu opens above its tab.
    ignoreNextRelease:       bool                   // Whether to ignore the release that opened the popup.
    popupHasGlyphs:          bool                   // Whether visible popup entries need the shared glyph column.
    popupHasMarkerColumn:    bool                   // Whether left-opening arrows own one shared leading column.
}

// Returns an icon's requested tint, or the row's text tint for an untinted icon.
private func menuIconColor(icon: Icon, textColor: Color)->Color => icon.color.a ? icon.color : textColor

public impl IWnd for MenuCtrl
{
    private mtd paintBar(painter: *Painter)
    {
        let theme   = .theme()
        let colors  = .themeColors()
        let rects   = .themeRects()
        let metrics = .themeMetrics()

        if .dirtyLayout
        {
            .dirtyLayout = false
            .computeLayoutBar()
        }

        // Back
        let clientRect = .clientRect()
        if .backgroundStyle != .Transparent
        {
            theme.drawSubRect(painter, clientRect, &rects.menuBar_Bk, colors.menuBar_Bk)
            theme.drawSubRect(painter, clientRect, &rects.menuBar_Border, colors.menuBar_Border)
        }

        var labelPos:       Math.Rectangle
        var colorText:      Color
        var colorRightText: Color

        for i, idx in .items
        {
            let it = unwrap i
            if it.hidden do
                continue
            if it.separator do
                continue

            labelPos = .getBarLabelRect(i)

            var format: RichStringFormat
            colorText      = it.disabled ? colors.popupItem_DisabledText : colors.popupItem_Text
            colorRightText = it.disabled ? colors.popupItem_DisabledText : colors.popupItem_RightText

            // Back selection
            let selected = not it.disabled and (.hotIdx == idx or .selectedIdx == idx)
            var colorSel: Color
            if selected
            {
                colorSel       = colors.menuBar_SelectedBk
                colorText      = colors.menuBar_SelectedText
                colorRightText = colors.popupItem_HotRightText
            }

            var backPos = labelPos
            backPos.x     -= metrics.menuBar_SpaceBetween * 0.5
            backPos.width += metrics.menuBar_SpaceBetween
            if selected and it.popup != null and .subVisible == it.popup
            {
                // Fill past the bar, outline only to it — the same split the popup makes in
                // [[Gui.MenuCtrl.paintPopupBarAnchor]], and for the same reason.
                var anchorBk = backPos
                anchorBk.height += metrics.menuPopup_BarItemOverlap
                theme.drawSubRect(painter, anchorBk, &rects.menuPopup_BarAnchorBk, colors.menuPopup_Bk)

                var anchorBorder = anchorBk
                anchorBorder.setBottom(backPos.bottom() + metrics.wnd_BorderSize)
                theme.drawSubRect(painter, anchorBorder, &rects.menuPopup_BarAnchorBorder, colors.menuPopup_Border, interpol: .Pixel)
            }
            elif selected and (it.popup != null)
            {
                theme.drawSubRect(painter, backPos, &rects.menuBar_PopupSelectedBk, colors.menuPopup_Bk)
                theme.drawSubRect(painter, backPos, &rects.menuBar_PopupSelectedBorder, colors.menuPopup_Border, interpol: .Pixel)
            }
            else
            {
                theme.drawSubRect(painter, backPos, &rects.menuBar_SelectedBk, colorSel)
            }

            // Icon
            if it.icon.isValid()
            {
                var icon = it.icon
                icon.sizeX, icon.sizeY = metrics.menuPopup_IconSize
                icon.paint(painter, labelPos.x, opticalTop(.font(), labelPos.vertCenter(), icon.sizeY), menuIconColor(icon, colorText))
            }

            // Text
            theme.setTextColors(&format, colorText)
            format.horzAlignment = .Left
            format.vertAlignment = .Center
            format.flags         = .Clip
            format.font          = .font()
            painter.drawRichString(labelPos, &it.name, format)
        }
    }

    private mtd paintPopup(painter: *Painter)
    {
        let theme   = .theme()
        let colors  = .themeColors()
        let rects   = .themeRects()
        let metrics = .themeMetrics()

        // Shadow. The anchor band carries the attached bar item or button, not the body, so the
        // shadow spans everything but that band: below the body when the popup hangs from a bar,
        // above it when the popup stands on its button.
        if not .paintByFrame
        {
            let subRect      = &theme.rects.menuPopup_Shadow
            let anchorHeight = .getPopupBarAnchorHeight()
            let shadowY      = .popupButtonOpensUp ? 0 : anchorHeight
            theme.drawSubRect(painter, Math.Rectangle{0, shadowY, .position.width, .position.height - anchorHeight}, subRect, colors.menuPopup_Shadow)
        }

        // Back
        var clientRect = .getPopupBodyRect()
        if not .paintByFrame
        {
            theme.drawSubRect(painter, clientRect, &rects.menuPopup_Bk, colors.menuPopup_Bk)
            theme.drawSubRect(painter, clientRect, &rects.menuPopup_Border, colors.menuPopup_Border, interpol: .Pixel)
        }

        .paintPopupBarAnchor(painter, clientRect)
        clientRect.applyPadding(.padding)

        var labelPos:       Math.Rectangle
        var colorText:      Color
        var colorRightText: Color

        var lastIsSeparator = true
        for i, idx in .items
        {
            let it = unwrap i
            if it.hidden do
                continue
            if it.separator and lastIsSeparator do
                continue

            labelPos.x      = clientRect.x
            labelPos.y      = it.pos
            labelPos.width  = clientRect.width
            labelPos.height = it.size

            lastIsSeparator = it.separator
            if it.separator
            {
                let inset = metrics.menuPopup_SeparatorInset
                painter.drawLine(labelPos.x + inset, labelPos.vertCenter(), labelPos.right() - inset, labelPos.vertCenter(), Pen.createSolid(colors.menuPopup_Separator))
                continue
            }

            // A label opens a group in small spaced capitals, where the wording of the entries starts.
            if it.label
            {
                labelPos.moveLeft(.popupHasGlyphs ? metrics.menuPopup_IconTextMargin + metrics.menuPopup_IconSize : metrics.menuPopup_IconMargin)
                SectionLabel.paint(me, painter, labelPos, it.name.raw)
                continue
            }

            colorText      = it.disabled ? colors.popupItem_DisabledText : (it.critical ? colors.critical : colors.popupItem_Text)
            colorRightText = it.disabled ? colors.popupItem_DisabledText : colors.popupItem_RightText

            // Back selection
            var colorSel: Color
            let isHot = .hotIdx == idx and not it.disabled
            if isHot
            {
                colorSel       = colors.popupItem_HotBk
                colorText      = colors.popupItem_HotText
                colorRightText = colors.popupItem_HotRightText
            }

            let markerColor  = it.disabled ? colors.popupItem_DisabledMarker : (isHot ? colors.popupItem_HotMarker : colors.popupItem_Marker)
            let submenuColor = it.disabled ? colors.popupItem_DisabledSubmenuMarker : (isHot ? colors.popupItem_HotSubmenuMarker : colors.popupItem_SubmenuMarker)

            var backPos = labelPos
            backPos.y      -= metrics.menuPopup_SpaceLines * 0.5
            backPos.height += metrics.menuPopup_SpaceLines
            backPos.inflate(.paddingSel, 0)
            theme.drawSubRect(painter, backPos, &rects.menuPopup_HotBk, colorSel)

            var iconPos = labelPos
            iconPos.x += metrics.menuPopup_IconMargin

            // When left-opening arrows are the only leading signs of this popup, they own one
            // shared minimal column: every wording then starts at the same place whether or not
            // its row carries the arrow, instead of the arrowed rows drifting to the right.
            var submenuMarkerX: f32
            if .popupHasMarkerColumn
            {
                submenuMarkerX = iconPos.x
                iconPos.x      += metrics.chevron_Size + metrics.menuPopup_IconTextMargin
                labelPos.moveLeft(metrics.chevron_Size + metrics.menuPopup_IconTextMargin)
            }

            labelPos.moveLeft(.popupHasGlyphs ? metrics.menuPopup_IconTextMargin + metrics.menuPopup_IconSize : metrics.menuPopup_IconMargin)
            labelPos.width -= metrics.menuPopup_IconSize

            // A left-opening submenu uses the shared glyph column when the row has no glyph of
            // its own. Reserving another column after the marker left a conspicuous hole before
            // the wording. A row that genuinely has both a marker and a glyph still keeps both.
            if it.popup != null
            {
                if it.submenuOpensLeft and not .popupHasMarkerColumn
                {
                    submenuMarkerX = iconPos.x
                    if not .popupHasGlyphs or it.icon.isValid()
                    {
                        iconPos.x += metrics.chevron_Size + metrics.menuPopup_IconTextMargin
                        labelPos.moveLeft(metrics.chevron_Size + metrics.menuPopup_IconTextMargin)
                    }
                }
                elif not it.submenuOpensLeft
                {
                    labelPos.width -= metrics.chevron_Size + metrics.menuPopup_IconTextMargin

                    // The chevron belongs to the trailing edge, not to the text column. The
                    // popup padding already supplies its outer air; keeping an extra icon-width
                    // reserve after it made the marker float conspicuously toward the wording.
                    // Let the chevron enter half the leading icon margin so its optical edge sits
                    // a little nearer the popup outline without crowding it.
                    submenuMarkerX = clientRect.right() - metrics.chevron_Size + metrics.menuPopup_IconMargin * 0.5
                }
            }

            // Text
            var format: RichStringFormat
            theme.setTextColors(&format, colorText)
            format.horzAlignment = .Left
            format.vertAlignment = .Center
            format.flags         = .Clip
            format.font          = .font()
            painter.drawRichString(labelPos, &it.name, format)

            // Everything standing on the entry's line — the check mark, the glyph, the
            // submenu arrow — is levelled with the wording, not with the row.
            let textCenterY = labelPos.vertCenter()

            // Marker: a check mark for an option that is on, the dot of a radio button for the
            // entry of an exclusive group that is chosen. The other entries of the group carry
            // nothing: a ring on every one of them would say "choice" as many times as there
            // are entries, where the one dot already says which is taken.
            //
            // The mark closes the row at its trailing edge, in the column a submenu arrow takes,
            // so the wording of every entry starts at the same place whether it is on or not and
            // the leading column belongs to glyphs alone.
            if it.checked
            {
                var checkPos: Math.Rectangle
                checkPos.x = clientRect.right() - metrics.menuPopup_IconSize + metrics.menuPopup_IconMargin * 0.5
                checkPos.y = opticalTop(.font(), textCenterY, metrics.menuPopup_IconSize)
                checkPos.width, checkPos.height = metrics.menuPopup_IconSize

                if it.rg == .ExclusiveGroup do
                    theme.drawSubRect(painter, checkPos, &rects.btnRadio_CheckedMark, markerColor)
                else do
                    theme.drawSubRect(painter, checkPos, &rects.btnCheck_CheckedMark, markerColor)
            }

            if it.icon.isValid()
            {
                var icon = it.icon
                icon.sizeX, icon.sizeY = metrics.menuPopup_IconSize
                icon.paint(painter, iconPos.x, opticalTop(.font(), textCenterY, icon.sizeY), menuIconColor(icon, colorText))
            }

            // A shortcut is a measure, so it is written in the fixed-width face, small and faint.
            if not .flags.has(.HideShortcuts) and not it.rightName.isEmpty()
            {
                format.palette[0]    = colorRightText
                format.horzAlignment = .Right
                format.vertAlignment = .Center
                format.flags         = .Clip
                format.font          = theme.createDefaultFontFamilyFs(metrics.menuPopup_ShortcutSize)
                painter.drawRichString(labelPos, &it.rightName, format)
            }

            // Submenu marker
            if it.popup != null
            {
                let glyph = it.submenuOpensLeft ? ThemeIcons.ChevronLeft : ThemeIcons.ChevronRight
                let icon  = theme.icon(glyph, metrics.chevron_Size)
                icon.paint(painter, submenuMarkerX, opticalTop(.font(), textCenterY, icon.sizeY), submenuColor)
            }
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        .frameWnd.IWnd.onPaint(evt)
        if .bar do
            .paintBar(evt.paintContext.painter)
        else do
            .paintPopup(evt.paintContext.painter)
    }

    mtd impl onTimerEvent(_: *TimerEvent)
    {
        .hideSubVisible()
        .removeTimer()
        .showHotPopup()
    }

    // A resolver is read while the layout is computed, and a menu bar only recomputes it
    // when something marks it dirty. A longer translation also changes where every entry
    // after it starts, so the whole bar has to be measured again.
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .dirtyLayout = true
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let hit = .hitTest(evt.surfacePos)
        if hit != .hotIdx
        {
            // Timer to auto open/hide sub menus
            if not .bar
            {
                if not .timer do
                    .timer = .surface!.app.addTimer(300'ms, me)
                .timer.restart()
            }

            .hotIdx = hit
            .invalidate()

            if hit != Swag.U32.Max
            {
                var p = .ownerMenu
                while p
                {
                    p.removeTimer()
                    p = p.ownerMenu
                }
            }
        }

        evt.accepted = true
        if .ignoreNextRelease and evt.kind == .Released and evt.button == .Left
        {
            .ignoreNextRelease = false
            return
        }

        if .hotIdx == Swag.U32.Max and .ownerMenu
        {
            .ownerMenu.onMouseEvent(evt)
            return
        }

        if .hotIdx == Swag.U32.Max and .bar and not .subVisible
        {
            evt.accepted = false
            return
        }

        // If this is a bar, then track sub popup if one is currently open
        if .bar and .subVisible and .hotIdx != Swag.U32.Max
        {
            .hideSubVisible()
            .removeTimer()
            .showHotPopup()
        }

        elif .bar and evt.kind == .Pressed and evt.button == .Left and .hotIdx != Swag.U32.Max
        {
            .hideSubVisible()
            .removeTimer()
            .showHotPopup()
            if .subVisible do
                .subVisible.ignoreNextRelease = true
        }

        elif .bar and
             evt.kind == .Released and
             evt.button == .Left and
             .hotIdx != Swag.U32.Max and
             not .subVisible
        {
            .hideSubVisible()
            .removeTimer()
            .showHotPopup()
        }
        // On a popup menu, just react to press button
        elif evt.kind == .Released and evt.button == .Left
        {
            if .hotIdx != Swag.U32.Max
            {
                let hotItem = unwrap .items[.hotIdx]
                if hotItem.popup != null
                {
                    .hideSubVisible()
                    .removeTimer()
                    .showHotPopup()
                }
                elif not hotItem.separator and not hotItem.disabled
                {
                    .setEndModal(hotItem.id)
                }
            }
            else
            {
                .setEndModal(null)
            }
        }
    }
}

impl MenuCtrl
{
    private mtd shouldOpenSubmenuLeft(surfaceRect: Math.Rectangle, submenuWidth: f32)->bool
    {
        if .submenuDirection == .Left do
            return true
        if .submenuDirection == .Right do
            return false

        let popupParent   = unwrap .parent
        let bounds        = popupParent.clientRect()
        let metrics       = .themeMetrics()
        let parentTopLeft = popupParent.surfaceToLocal(Math.Point{surfaceRect.x, surfaceRect.y})
        let openRight     = parentTopLeft.x + surfaceRect.width - 2 * metrics.menuPopup_ShadowSize
        let openLeft      = parentTopLeft.x - submenuWidth + 2 * metrics.menuPopup_ShadowSize
        let margin        = metrics.menuPopup_WindowMargin
        if openRight + submenuWidth <= bounds.right() - margin do
            return false
        if openLeft >= bounds.x + margin do
            return true
        return parentTopLeft.x - bounds.x > bounds.right() - parentTopLeft.x - surfaceRect.width
    }

    private mtd resolveSubmenuDirections()
    {
        // Every submenu of a menu opens on one side, the side its widest one fits: chevrons that
        // point both ways on neighbouring entries read as two kinds of entry.
        let surfaceRect = .surfaceRect()
        var widest      = 0'f32
        for i in .items where i!.popup != null and not i.hidden
        {
            let item = i
            item.popup.updateState()
            item.popup.computeLayoutPopup()
            widest = Math.max(widest, item.popup.position.width)
        }

        let opensLeft = widest > 0 and .shouldOpenSubmenuLeft(surfaceRect, widest)
        for i in .items where i!.popup != null and not i.hidden do
            i.submenuOpensLeft = opensLeft

        .invalidate()
    }

    private mtd hasPopupBarAnchor()->bool => (.popupBarItemIdx != Swag.U32.Max and .ownerMenu and .ownerMenu.bar) or .popupAnchorButton != null

    private mtd clearPopupBarAnchor()
    {
        .popupBarItemIdx = Swag.U32.Max
        .popupBarItemSurfaceRect.clear()
        .popupAnchorButton  = null
        .popupButtonOpensUp = false
    }

    private mtd setPopupBarAnchor(itemIdx: u32, itemSurfaceRect: Math.Rectangle)
    {
        .popupBarItemIdx         = itemIdx
        .popupBarItemSurfaceRect = itemSurfaceRect
    }

    private mtd setPopupButtonAnchor(button: *IconButton)
    {
        .popupAnchorButton       = button
        .popupBarItemSurfaceRect = button.surfaceRect()
        .popupButtonOpensUp      = button.arrowPosition == .RightUpward
    }

    internal mtd getPopupBarAnchorHeight()->f32 => .hasPopupBarAnchor() ? .popupBarItemSurfaceRect.height : 0

    // Reports whether the body of an attached popup still fits on the side its tab opens to.
    //
    // The tab, the mouth it opens in the body's outline and the hairline that continues that
    // outline are all placed against one edge of the body, so the body has to stay where its
    // button is. A body that does not fit is moved by the window fit afterwards, and the tab
    // then describes an edge the body no longer has.
    private mtd popupButtonAnchorFits()->bool
    {
        let parent = unwrap .parent
        let shadow = .themeMetrics().menuPopup_ShadowSize
        let anchor = .popupBarItemSurfaceRect
        let local  = parent.surfaceToLocal(Math.Point{anchor.x, anchor.y})

        if .popupButtonOpensUp do
            return local.y - (.position.height - anchor.height - shadow) >= -shadow
        return local.y - shadow + .position.height <= parent.position.height + shadow
    }

    // Settles which side an attached popup opens to, and gives the attachment up when it fits on
    // neither.
    //
    // A menu taller than the room on both sides of its button is not attached to anything any
    // more: it opens as an ordinary popup, hanging from under the button and clamped to the
    // window, rather than as a tab drawn against an edge that has slid away from it.
    private mtd fitPopupButtonAnchor()
    {
        if .popupButtonAnchorFits() do
            return

        .popupButtonOpensUp = not .popupButtonOpensUp
        .computeLayoutPopup()
        if .popupButtonAnchorFits() do
            return

        .clearPopupBarAnchor()
        .computeLayoutPopup()
    }

    private mtd getPopupBarAnchorLocalRect()->Math.Rectangle
    {
        var result: #returntype = .popupBarItemSurfaceRect
        let surfaceRect         = .surfaceRect()
        result.x -= surfaceRect.x
        result.y -= surfaceRect.y
        return result
    }

    private mtd getBarItemHeight()->f32 => Math.min(.clientRect().height, .themeMetrics().menuBar_Height)

    private mtd getBarLabelRect(item: *PopupMenuItem)->Math.Rectangle
    {
        let clientRect = .clientRect()
        let height     = .getBarItemHeight()
        return Math.Rectangle{
            item.pos,
            clientRect.y + (clientRect.height - height) * 0.5,
            item.size,
            height}
    }

    private mtd getBarItemRect(item: *PopupMenuItem)->Math.Rectangle
    {
        let metrics = .themeMetrics()
        var result  = .getBarLabelRect(item)
        result.x     -= metrics.menuBar_SpaceBetween * 0.5
        result.width += metrics.menuBar_SpaceBetween
        return result
    }

    internal mtd getPopupBodyRect()->Math.Rectangle
    {
        let metrics             = .themeMetrics()
        var result: #returntype = .clientRect()
        let anchorHeight        = .getPopupBarAnchorHeight()
        if anchorHeight
        {
            result.height -= anchorHeight
            if not .popupButtonOpensUp do
                result.y += anchorHeight
        }

        if not .paintByFrame do
            result.inflate(-metrics.menuPopup_ShadowSize)
        return result
    }

    private mtd paintPopupBarAnchor(painter: *Painter, bodyRect: Math.Rectangle)
    {
        if not .hasPopupBarAnchor() do
            return

        let theme   = .theme()
        let colors  = .themeColors()
        let metrics = .themeMetrics()

        let anchorRect = .getPopupBarAnchorLocalRect()
        if anchorRect.isEmpty() do
            return

        paintPopupAnchorTab(me, painter, anchorRect, bodyRect, .popupButtonOpensUp)
        if .popupAnchorButton
        {
            .popupAnchorButton.paintMenuAnchorContent(painter, anchorRect, colors.menuBar_SelectedText)
            return
        }

        let i        = unwrap .ownerMenu!.items[.popupBarItemIdx]
        var labelPos = anchorRect
        labelPos.x     += metrics.menuBar_SpaceBetween * 0.5
        labelPos.width -= metrics.menuBar_SpaceBetween

        var format: RichStringFormat
        let colorText = i.disabled ? colors.popupItem_DisabledText : colors.menuBar_SelectedText
        theme.setTextColors(&format, colorText)
        format.horzAlignment = .Left
        format.vertAlignment = .Center
        format.flags         = .Clip
        format.font          = .font()

        if i.icon.isValid()
        {
            var icon = i.icon
            icon.sizeX, icon.sizeY = metrics.menuPopup_IconSize
            icon.paint(painter, labelPos.x, opticalTop(.font(), labelPos.vertCenter(), icon.sizeY), menuIconColor(icon, colorText))
        }

        painter.drawRichString(labelPos, &i.name, format)
    }

    mtd setEndModal(result: WndId?)
    {
        var p = me
        while p.ownerMenu
        {
            p.hide()
            p = p.ownerMenu
        }

        p.endModal       = true
        p.endModalResult = result

        // A transient root disappears in the same input event as its selected leaf. Mark it
        // visually hidden now, but leave teardown to doModal: unregistering it while its mouse
        // event is still being dispatched can prevent the selected command from being posted.
        if not p.bar
        {
            p.wndFlags.add(.Hidden)
            p.parent!.invalidate()
        }

        if result != null do
            .sigCommandSelected.call(me, result)

        if .bar
        {
            .hideSubVisible()
            .postCommandEvent(result)
            .setFocus()
        }

        if p.bar
        {
            p.selectedIdx = Swag.U32.Max
            p.hotIdx      = Swag.U32.Max
            p.subVisible  = null
            p.postCommandEvent(result)
        }
    }

    mtd hideSubVisible()
    {
        while .subVisible
        {
            .subVisible.ignoreNextRelease = false
            .subVisible.hide()
            .subVisible = .subVisible.subVisible
        }

        .selectedIdx = Swag.U32.Max
        if not .bar do
            .captureMouse()
        else do
            .releaseMouse()
    }

    mtd removeTimer()
    {
        if not .timer do
            return
        .surface!.app.removeTimer(.timer)
        .timer = null
    }

    // Refreshes every item from the command state its identifier computes.
    //
    // The label, icon, shortcut, and flags an answer updates replace those of the item.
    public mtd updateState()
    {
        for i in .items
        {
            let it  = unwrap i
            let evt = .sendComputeCommandStateEvent(it.id)
            if evt.updatedFields.has(.Disabled) do
                it.disabled = evt.disabled
            if evt.updatedFields.has(.Hidden) do
                it.hidden = evt.hidden
            if evt.updatedFields.has(.Icon) do
                it.icon = evt.icon
            if evt.updatedFields.has(.LongName) do
                it.name = evt.longName
            elif evt.updatedFields.has(.Name) do
                it.name = evt.name
            if evt.updatedFields.has(.Shortcut) do
                it.rightName.set(evt.shortcut)
            if evt.updatedFields.has(.Checked) do
                it.checked = evt.checked
            if evt.updatedFields.has(.RenderingHint) do
                it.rg = evt.renderingHint
        }
    }

    mtd showSubVisible(ptSurface: Math.Point)
    {
        with me.subVisible
        {
            let pt = .parent!.surfaceToLocal(ptSurface)
            .setPosition(Math.Rectangle{pt.x, pt.y, .position.width, .position.height})
            .resolveSubmenuDirections()
            .bringToFront()
            .show()
            .captureMouse()
            .hotIdx      = Swag.U32.Max
            .selectedIdx = Swag.U32.Max
            .subVisible  = null
            .timer       = null
        }
    }

    mtd showHotPopupBar()
    {
        .selectedIdx = .hotIdx
        let hotItem = unwrap .items[.hotIdx]
        let metrics = .themeMetrics()

        var anchorRect = .localToSurface(.getBarItemRect(hotItem))

        var pos = anchorRect
        pos.x -= metrics.menuPopup_ShadowSize
        pos.y -= metrics.menuPopup_ShadowSize
        let sub = hotItem.popup
        .subVisible = sub
        sub.ignoreNextRelease = false
        sub.setPopupBarAnchor(.hotIdx, anchorRect)

        // Keep the popup body in the client area. Its shadow may fall outside the parent; clamping
        // the whole window moves the attached body away from the bar at the top and side edges.
        sub.updateState()
        sub.computeLayoutPopup()

        // A caption menu is a sibling of the application view. Clamping it in topView space
        // shifts its anchor down by the whole caption/client inset, so the opening tab grows a
        // false stem as tall as the command row below it. The popup's actual parent owns both
        // the caption and the client area, and is therefore the coordinate space that can keep
        // the popup inside the surface without moving it away from its bar item.
        let popupParent = unwrap sub.parent
        let bounds      = popupParent.clientRect()
        var pt          = popupParent.surfaceToLocal(Math.Point{pos.x, pos.y})
        let subPos      = sub.position
        let shadow      = metrics.menuPopup_ShadowSize
        pt.x = Math.clamp(pt.x, bounds.x - shadow, Math.max(bounds.right() - subPos.width + shadow, bounds.x - shadow))
        pt.y = Math.clamp(pt.y, bounds.y - shadow, Math.max(bounds.bottom() - subPos.height + shadow, bounds.y - shadow))

        pt = popupParent.localToSurface(pt)
        .showSubVisible(pt)
    }

    mtd showHotPopupPopup()
    {
        .selectedIdx = .hotIdx
        let hotItem = unwrap .items[.hotIdx]

        let surfaceRect = .surfaceRect()
        let sdw         = .themeMetrics().menuPopup_ShadowSize
        let sub         = hotItem.popup
        .subVisible = sub
        sub.ignoreNextRelease = false
        sub.clearPopupBarAnchor()

        // Keep the submenu in the same presentation layer as the popup that owns it. Menus from
        // client content live in the top view; menus from surface chrome live above that view.
        sub.updateState()
        sub.computeLayoutPopup()
        let popupParent   = unwrap sub.parent
        let bounds        = popupParent.clientRect()
        let parentTopLeft = popupParent.surfaceToLocal(Math.Point{surfaceRect.x, surfaceRect.y})
        let subPos        = sub.position
        let openRight     = parentTopLeft.x + surfaceRect.width - 2 * sdw
        let openLeft      = parentTopLeft.x - subPos.width + 2 * sdw
        hotItem.submenuOpensLeft = .shouldOpenSubmenuLeft(surfaceRect, subPos.width)
        var pt = Math.Point{hotItem.submenuOpensLeft ? openLeft : openRight, parentTopLeft.y + hotItem.pos - .padding.y - sdw}

        // Keep the complete submenu inside the window when possible, with the same outer air as
        // its root. An oversized menu is clamped on the requested side as a last resort.
        let margin = .themeMetrics().menuPopup_WindowMargin
        pt.x = Math.clamp(pt.x, bounds.x + margin, Math.max(bounds.right() - subPos.width - margin, bounds.x + margin))
        pt.y = Math.clamp(pt.y, bounds.y + margin, Math.max(bounds.bottom() - subPos.height - margin, bounds.y + margin))

        pt = popupParent.localToSurface(pt)
        .showSubVisible(pt)
    }

    mtd showHotPopup()
    {
        if .hotIdx == Swag.U32.Max or .items[.hotIdx]!.popup == null
        {
            .selectedIdx = Swag.U32.Max
            return
        }

        if .bar do
            .showHotPopupBar()
        else do
            .showHotPopupPopup()
    }

    mtd hitTestBar(surfacePos: Math.Point)->u32
    {
        let pos = .surfaceToLocal(surfacePos)
        for iIt, idx in .items
        {
            let i = unwrap iIt
            if i.hidden do
                continue
            if i.separator do
                continue

            if .getBarItemRect(i).contains(pos) do
                return cast(u32, idx)
        }

        return Swag.U32.Max
    }

    mtd hitTestPopup(surfacePos: Math.Point)->u32
    {
        let pos             = .surfaceToLocal(surfacePos)
        let metrics         = .themeMetrics()
        let clientRect      = .clientRect()
        let sl              = metrics.menuPopup_SpaceLines
        var lastIsSeparator = true
        for i, idx in .items
        {
            let it = unwrap i
            if it.hidden do
                continue
            if it.separator and lastIsSeparator do
                continue

            let rect = Math.Rectangle{clientRect.x, it.pos - sl * 0.5, clientRect.width, it.size + sl}
            if rect.contains(pos) do
                return cast(u32, idx)

            lastIsSeparator = it.separator
        }

        return Swag.U32.Max
    }

    mtd hitTest(surfacePos: Math.Point)->u32 => .bar ? .hitTestBar(surfacePos) : .hitTestPopup(surfacePos)

    mtd computeLayoutBar()
    {
        let metrics    = .themeMetrics()
        let clientRect = .paddedClientRect()

        var x = clientRect.x

        // Measured at the density the glyphs are really drawn at. Laid out at a scale of
        // one and drawn at another, the run comes out a touch wider than the width reserved
        // for it and the entry loses its last letter to the clip.
        let deviceScale = .deviceScale()
        var rsf: Pixel.RichStringFormat
        rsf.font = .font()

        for i in .items
        {
            let it = unwrap i
            if it.hidden do
                continue
            if .onPrepareItem do
                .onPrepareItem(i)
            if it.nameResolver do
                it.name.set(it.nameResolver())
            it.pos = x + metrics.menuBar_SpaceBetween * 0.5
            it.name.compute()
            Pixel.Painter.computeLayout({0, 0, MaxTextLayoutExtent, MaxTextLayoutExtent}, &it.name, rsf, deviceScale)
            it.size = it.name.boundRect.width
            x       = it.pos + it.size + metrics.menuBar_SpaceBetween * 0.5
        }
    }

    // Recomputes the size of a popup menu and the position of each of its items.
    public mtd computeLayoutPopup()
    {
        let metrics = .themeMetrics()

        var clientRect = .getPopupBodyRect()
        clientRect.applyPadding(.padding)

        .position.width  = 0
        .position.height = clientRect.y

        // Measured at the density the glyphs are really drawn at; see computeLayoutBar.
        let deviceScale = .deviceScale()
        var rsf: Pixel.RichStringFormat
        rsf.font = .font()

        var lastIsSeparator = true
        var hasSubmenuRows  = false
        .popupHasGlyphs = false
        for i, idx in .items
        {
            let it = unwrap i
            if it.hidden do
                continue
            if it.separator and lastIsSeparator do
                continue

            if .onPrepareItem do
                .onPrepareItem(i)
            if it.nameResolver do
                it.name.set(it.nameResolver())
            if idx do
                .position.height += metrics.menuPopup_SpaceLines
            it.pos = .position.height

            lastIsSeparator = it.separator
            if it.separator
            {
                it.size = metrics.menuPopup_SeparatorHeight
                .position.height += it.size
                continue
            }

            if it.icon.isValid() do
                .popupHasGlyphs = true

            // `menuPopup_ItemHeight` is the complete row pitch. The inter-entry air is
            // accounted for separately so the text box keeps only the remaining height.
            it.size = Math.max(rsf.font.regular!.height, metrics.menuPopup_ItemHeight - metrics.menuPopup_SpaceLines)

            it.name.compute()
            Pixel.Painter.computeLayout({0, 0, MaxTextLayoutExtent, MaxTextLayoutExtent}, &it.name, rsf, deviceScale)
            var w = it.name.boundRect.width

            if not .flags.has(.HideShortcuts) and not it.rightName.isEmpty()
            {
                var shortcutFormat = rsf
                shortcutFormat.font = .theme().createDefaultFontFamilyFs(metrics.menuPopup_ShortcutSize)
                it.rightName.compute()
                Pixel.Painter.computeLayout({0, 0, MaxTextLayoutExtent, MaxTextLayoutExtent}, &it.rightName, shortcutFormat, deviceScale)
                w += it.rightName.boundRect.width + rsf.font.regular.height * 3
            }

            // A submenu row paints a chevron after the text column. Reserve that band while
            // measuring too, otherwise the row is exactly wide enough only until the chevron is
            // subtracted at paint time and its last word is clipped.
            if it.popup != null
            {
                hasSubmenuRows = true
                w += metrics.chevron_Size + metrics.menuPopup_IconTextMargin
            }

            .position.width  = Math.max(.position.width, w)
            .position.height += it.size
        }

        // Add shadow size
        if not .paintByFrame do
            .position.width += 2 * metrics.menuPopup_ShadowSize

        let leadingWidth = .popupHasGlyphs ? metrics.menuPopup_IconSize + metrics.menuPopup_IconTextMargin : metrics.menuPopup_IconMargin
        .position.width += metrics.menuPopup_IconSize + leadingWidth

        // With no glyph column to share, a popup whose submenus deliberately open on the left
        // aligns everything on one arrow column instead; the column has to be paid for once,
        // since the rows without an arrow reserved nothing for it.
        .popupHasMarkerColumn = hasSubmenuRows and .submenuDirection == .Left and not .popupHasGlyphs
        if .popupHasMarkerColumn do
            .position.width += metrics.chevron_Size + metrics.menuPopup_IconTextMargin

        if .hasPopupBarAnchor() and not .paintByFrame
        {
            let bodyWidth = .position.width - 2 * metrics.menuPopup_ShadowSize
            if bodyWidth < .popupBarItemSurfaceRect.width do
                .position.width += .popupBarItemSurfaceRect.width - bodyWidth
        }

        if not .paintByFrame do
            .position.height += metrics.menuPopup_ShadowSize

        // Add padding
        .position.width  += .padding.x + .padding.z
        .position.height += .padding.w
        if .popupButtonOpensUp do
            .position.height += .getPopupBarAnchorHeight()
    }
}

public impl MenuCtrl
{
    // Selects whether an enclosing frame paints the popup border and shadow.
    mtd setFramePainting(enabled: bool)
    {
        if .paintByFrame == enabled do
            return
        .paintByFrame = enabled
        .dirtyLayout  = true
        .invalidate()
    }

    // Selects the side used by child menus and their chevron markers.
    //
    // [[Gui.SubmenuDirection.Automatic]] keeps the conventional right side while it fits and
    // switches both the child menu and its marker to the left near the window edge.
    mtd setSubmenuDirection(direction: SubmenuDirection)
    {
        if .submenuDirection == direction do
            return
        .submenuDirection = direction
        .invalidate()
    }

    // Reports whether the current modal popup loop has ended.
    mtd const isModalEnded()->bool => .endModal

    // Returns the selected modal command, or null when dismissed or still running.
    mtd const modalResult()->WndId? => .endModalResult

    // Adds and removes presentation options, then invalidates cached layout.
    mtd updateFlags(add: MenuFlags = .None, remove = MenuFlags.None)
    {
        var flags = .flags
        flags.add(add)
        flags.remove(remove)
        if flags == .flags do
            return
        .flags       = flags
        .dirtyLayout = true
        .invalidate()
    }

    // Creates a hidden popup menu in the presentation layer containing `parent`.
    //
    // Client controls place their menus in the root content view. Surface chrome and existing
    // surface overlays place them in the root surface window, so the complete menu tree can cross
    // the content inset without being clipped. `owner`, or `parent` when omitted, remains the
    // logical owner for command routing.
    #[Swag.Discardable]
    func createPopup(parent: *Wnd, id: WndId? = null, owner: *Wnd? = null)->*MenuCtrl
    {
        Swag.assert(parent != null)
        let topView     = parent.topView()
        let popupParent = parent == topView or topView.isAncestorOf(parent) ? topView : parent.topWindow()
        with let res    = Wnd.create'MenuCtrl(popupParent, null, {}, id)
        {
            .focusPolicy = .Click
            .owner       = owner orelse parent
            .setAllPaddings(.themeMetrics().menuPopup_Padding)
            .style.addStyleSheetColors("frameWnd_Border $menuPopup_Border")
            .wndFlags |= .Hidden
        }

        return res
    }

    // Creates a persistent horizontal menu bar.
    #[Swag.Discardable]
    func createBar(parent: *Wnd, pos: Math.Rectangle = {}, id: WndId? = null, owner: *Wnd? = null)->*MenuCtrl
    {
        Swag.assert(parent != null)
        with let res = Wnd.create'MenuCtrl(parent, null, pos, id)
        {
            .focusPolicy = .Click
            .owner       = owner
            let metrics = .themeMetrics()
            if .position.height == 0 do
                .position.height = metrics.menuBar_Height
            .setAllPaddings(metrics.menuPopup_Padding)
            .bar = true
        }

        return res
    }

    // Returns the item at `index`.
    mtd const itemAt(index: u32)->*PopupMenuItem
    {
        Swag.assert(index < .items.count, "menu item index is out of range")
        return unwrap .items[index]
    }

    // Removes one item and invalidates cached menu layout.
    mtd removeItemAt(index: u32)
    {
        Swag.assert(index < .items.count, "menu item index is out of range")
        .hideSubVisible()
        .removeTimer()
        .items.deleteAt(index)
        .hotIdx      = Swag.U32.Max
        .selectedIdx = Swag.U32.Max
        .dirtyLayout = true
        .invalidate()
    }

    // Removes every command, submenu entry, and separator.
    mtd clear()
    {
        if .items.isEmpty() do
            return
        .hideSubVisible()
        .removeTimer()
        .items.clear()
        .hotIdx      = Swag.U32.Max
        .selectedIdx = Swag.U32.Max
        .dirtyLayout = true
        .invalidate()
    }

    // Adds a command whose label, icon, and state come from its command identifier.
    #[Swag.Discardable]
    mtd addItem(id: WndId)->*PopupMenuItem => .addItem(null, id)

    // Adds commands whose labels, icons, and states come from their identifiers.
    mtd addItems(ids: const [..] WndId)
    {
        for id in ids do
            .addItem(null, id)
    }

    // Adds a command group followed by a separator.
    mtd addGroup(ids: const [..] WndId)
    {
        .addItems(ids)
        .addSeparator()
    }

    // Adds a command with explicit presentation and returns its mutable item descriptor.
    #[Swag.Discardable]
    mtd addItem(name: string?, id: WndId, icon: Icon = {}, rightName: string? = null, disabled = false, checked = false)->*PopupMenuItem
    {
        with let mitem = me.items.allocate()
        {
            .name.set(name)
            .icon      = icon
            .id        = id
            .rightName = rightName orelse ""
            .disabled  = disabled
            .checked   = checked
        }

        .items.add(mitem)
        .dirtyLayout = true
        return mitem
    }

    // Adds a command of a mutually exclusive group and returns its mutable item descriptor.
    //
    // The chosen entry carries the dot of a radio button rather than a check mark, and the
    // other entries of the group carry nothing, so the reader sees one choice rather than a set
    // of independent toggles. Add every entry of the group this way, the chosen one and the
    // others alike: the group still reserves its marker column so the wording stays aligned.
    #[Swag.Discardable]
    mtd addRadioItem(name: string?, id: WndId, checked = false, rightName: string? = null, disabled = false)->*PopupMenuItem
    {
        let mitem = .addItem(name, id, rightName: rightName, disabled: disabled, checked: checked)
        mitem.rg = .ExclusiveGroup
        return mitem
    }

    // Adds a submenu whose presentation comes from a command identifier.
    #[Swag.Discardable]
    mtd addPopup(popup: *MenuCtrl, id: WndId)->*PopupMenuItem => .addPopup(name: null, popup: popup, id: id)

    // Adds a command whose label is re-read on every layout.
    //
    // Use this rather than a literal for a label that has to follow a language switch; see
    // [[Gui.MenuLabelResolver]].
    #[Swag.Discardable]
    mtd addItem(name: MenuLabelResolver, id: WndId, icon: Icon = {}, rightName: string? = null, disabled = false, checked = false)->*PopupMenuItem
    {
        with let mitem = .addItem(name(), id, icon, rightName, disabled, checked)
        {
            .nameResolver = name
        }

        return mitem
    }

    // Adds a submenu with explicit presentation and returns its mutable item descriptor.
    #[Swag.Discardable]
    mtd addPopup(name: string?, popup: *MenuCtrl, icon: Icon = {}, id: WndId? = null)->*PopupMenuItem
    {
        with let mitem = me.items.allocate()
        {
            .name.set(name)
            .icon  = icon
            .popup = popup
            .id    = id
        }

        popup.ownerMenu = me
        .items.add(mitem)
        .dirtyLayout = true
        return mitem
    }

    // Adds a submenu whose label is re-read on every layout.
    //
    // This is what a menu bar uses: `addPopup(name, popup)` copies the wording into the item
    // once, so the six entries of an application bar would otherwise keep the language they
    // were built in while everything below them refreshes through the command state.
    #[Swag.Discardable]
    mtd addPopup(name: MenuLabelResolver, popup: *MenuCtrl, icon: Icon = {}, id: WndId? = null)->*PopupMenuItem
    {
        with let mitem = .addPopup(name(), popup, icon, id)
        {
            .nameResolver = name
        }

        return mitem
    }

    // Adds the label opening a group of entries of a popup, such as "Presentation" above the ways
    // of showing a view, and returns it. It is written as a section label and is never chosen.
    #[Swag.Discardable]
    mtd addLabel(name: string)->*PopupMenuItem
    {
        with let item = me.items.allocate()
        {
            .name.set(name)
            .label    = true
            .disabled = true
        }

        .items.add(item)
        .dirtyLayout = true
        return item
    }

    // Adds a separator unless the menu is empty or already ends with one.
    //
    // Callers can therefore separate groups unconditionally without producing duplicate dividers.
    mtd addSeparator()
    {
        let last = .items.last()
        if not last or last.separator do
            return
        let item = .items.allocate()
        item.separator = true
        .items.add(item)
        .dirtyLayout = true
    }

    // Runs a popup menu joined to a [[Gui.IconButton]] and returns its selected command, or null when dismissed.
    //
    // The button is repainted as the popup's opening tab instead of pointing at a detached box
    // with a notch. A [[Gui.IconButtonArrowPosition.RightUpward]] marker opens the menu above the
    // button; every other marker opens it below. When `autoDestroy` is true, the menu destroys
    // itself after the modal loop.
    mtd doModal(button: *IconButton, autoDestroy: bool = false)->WndId? => .doModalImpl({}, .TopLeft, autoDestroy, button)

    // Runs a popup menu modally at `surfacePos` and returns its selected command, or null when dismissed.
    //
    // `pos` says how the menu is placed around `surfacePos`. When `autoDestroy` is true, the
    // menu destroys itself after the modal loop ends.
    mtd doModal(surfacePos: Math.Point, pos = PopupPosition.TopLeft, autoDestroy: bool = false)->WndId? => .doModalImpl(surfacePos, pos, autoDestroy, null)

    private mtd doModalImpl(surfacePos: Math.Point, pos: PopupPosition, autoDestroy: bool, button: *IconButton?)->WndId?
    {
        Swag.assert(not .bar)

        .clearPopupBarAnchor()
        if button do
            .setPopupButtonAnchor(button)
        .updateState()

        // Every popup paints its own ground, border and shadow: a menu centred on a point is shaped
        // like any other.
        .paintByFrame = false

        .computeLayoutPopup()
        if button do
            .fitPopupButtonAnchor()

        // Be sure popup menu is in the client area of the top view
        var pt = .parent!.surfaceToLocal(surfacePos)

        if button
        {
            let anchor = button.surfaceRect()
            let sdw    = .themeMetrics().menuPopup_ShadowSize

            var y = anchor.y - sdw
            if not .hasPopupBarAnchor() do
                y = anchor.bottom() - sdw
            elif .popupButtonOpensUp do
                y = anchor.y - (.position.height - anchor.height - sdw)

            pt = .parent.surfaceToLocal(Math.Point{anchor.x - sdw, y})
            .setPosition(Math.Rectangle{pt.x, pt.y, .position.width, .position.height})
        }

        else
        {
            switch pos
            {
            case .TopLeft:
                pt -= .themeMetrics().menuPopup_ShadowSize
                .setPosition(Math.Rectangle{pt.x, pt.y, .position.width, .position.height})

            case .TopRight:
                let shadow = .themeMetrics().menuPopup_ShadowSize
                .setPosition(Math.Rectangle{pt.x - .position.width + shadow, pt.y - shadow, .position.width, .position.height})

            // Centred on the point, as every menu is shaped: no tail, since a floating surface
            // says where it came from by leaving it, not by pointing at it.
            case .AnchorTopCenter:
                pt.y += .themeMetrics().menuPopup_ShadowSize
                .setPosition(Math.Rectangle{pt.x - .position.width * 0.5, pt.y, .position.width, .position.height})
                .anchorPosition = .position.width * 0.5

            case .AnchorBottomCenter:
                pt.y -= .themeMetrics().menuPopup_ShadowSize
                .setPosition(Math.Rectangle{pt.x - .position.width * 0.5, pt.y - .position.height, .position.width, .position.height})
                .anchorPosition = .position.width * 0.5
            }
        }

        let anchored = button != null or pos == .AnchorTopCenter or pos == .AnchorBottomCenter
        let margin   = .themeMetrics().menuPopup_WindowMargin

        // An attached button can sit against either surface edge, closer than the popup shadow is
        // deep. Let that invisible shadow start outside the surface on both axes; clamping it to
        // the normal window margin would detach the popup body from a right-aligned trigger. A
        // popup that gave its attachment up keeps the ordinary margin.
        let fitMargin = .hasPopupBarAnchor() ? -.themeMetrics().menuPopup_ShadowSize : margin
        .fitPosInParent(fitMargin, fitMargin, simX: not anchored, simY: true)

        // Fitting a centred popup near the right edge moves the body, not its attachment point.
        // Recompute the notch from the original anchor so it remains directly under the button.
        if anchored and not button do
            .anchorPosition = Math.clamp(pt.x - .position.x, 0.0, .position.width)

        .resolveSubmenuDirections()

        // The menu leaves its anchor by a few pixels: down from a button above it, up from one below.
        let anchorY = button ? button.surfaceRect().vertCenter() : surfacePos.y
        let travel  = .themeMetrics().motion_AnchorTravel
        .bringToFront()
        discard .app().animator.arrive(me, {0, .surfaceRect().vertCenter() < anchorY ? travel : -travel})
        .captureMouse()

        .endModal          = false
        .endModalResult    = null
        .app().inModalLoop += 1
        let srf = unwrap .surface
        while not .endModal do
            srf.app.runFrame()
        .app().inModalLoop -= 1

        // setEndModal can suppress the root before this loop resumes. Clear that presentation-only
        // flag so hide performs the normal focus, input and registration teardown exactly once.
        if .wndFlags.has(.Hidden) do
            .wndFlags.remove(.Hidden)
        .hideSubVisible()
        if autoDestroy do
            .hide()
        else do
            discard .app().animator.leave(me)

        if .endModalResult do
            .postCommandEvent(.endModalResult)

        if autoDestroy do
            .destroy()

        return .endModalResult
    }
}
