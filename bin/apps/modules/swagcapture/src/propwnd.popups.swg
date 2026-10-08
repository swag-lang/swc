impl PropWnd
{
    // One square style cell. `tip` names what the cell sets; the sample inside it shows the
    // current value, so the name is only needed when a reader asks for it.
    func createStyleButton(stack: *Wnd, tip: string)->*IconButton
    {
        with let button = IconButton.create(stack, {}, {0, 0, StyleCellSize, StyleCellSize})
        {
            .setForm(.Rectangle)
            .style.addStyleSheetColors("btnIcon_Bk                  $veilSoft")
            .style.addStyleSheetColors("btnIcon_HotBk               $veilMedium")
            .style.addStyleSheetColors("btnIcon_PressedBk           $veilStrong")
            .style.addStyleSheetColors("btnIcon_CheckedPressedIcon  $btnIcon_Text")
            .style.addStyleSheetColors("btnIcon_CheckedPressedText  $btnIcon_Text")

            .updateFlags(.Popup | .Toggle)
            .setArrowPosition(.None)
            .setCheckIndicator(.None)
            .toolTip = tip
        }

        return button
    }

    func createColorPicker(btn: *IconButton, color: Color)->*ColorPickerCtrl
    {
        let frame = btn.createAnchorPopup(356, 382)

        with var pal: Array'Color
        {
            .add(Argb.White)
            .add(Argb.Gray)
            .add(Argb.Black)
            .add(ColorRed)
            .add(ColorGreen)
            .add(ColorBlue)
            .add(ColorYellow)
            .add(Argb.Purple)
        }

        let picker = ColorPickerCtrl.createWithPalette(frame, {8, 54}, pal)
        picker.setColor(color)
        return picker
    }

    // Shared by the shape and step buttons: 'type' is the concrete form type and
    // 'fieldName' its FormShapeKind field, read back through reflection so both
    // forms go through the same popup.
    mtd createPopupShapeKind(btn: *IconButton, type: typeinfo, fieldName: string)
    {
        let cells  = cast(f32, FormShapeKind.count)
        let frame  = btn.createAnchorPopup(popupExtent(cells, PopupCellSize), popupExtent(1, PopupCellSize))
        let layout = frame.createView'WrapLayoutCtrl()
        layout.itemWidth, layout.itemHeight = PopupCellSize
        layout.spacing = PopupSpacing
        layout.padding = PopupPadding

        func selectedKind(prop: *PropWnd, type: typeinfo, fieldName: string)->FormShapeKind
        {
            var val: u32
            let field = Reflection.findField(type, fieldName)!
            Reflection.readFieldValue(&val, field, prop.getSelectedBaseForm())
            return cast(FormShapeKind, val)
        }

        func updateBtnState(prop: *PropWnd, layout: *Wnd, type: typeinfo, fieldName: string)
        {
            let cur = selectedKind(prop, type, fieldName)
            for c in layout.children
            {
                let button = assume cast(*IconButton, c)
                let kind   = enumFromUserData'FormShapeKind(button.userData)
                button.setChecked(cur == kind)
                button.invalidate()
            }
        }

        let cur = selectedKind(me, type, fieldName)

        for i in FormShapeKind.count
        {
            with let btn0 = IconButton.create(frame.view, {}, {0, 0, PopupCellSize, PopupCellSize})
            {
                .userData = enumToUserData(i)
                .setForm(.Rectangle)
                .updateFlags(.Radio)
                if cur == i do
                    .setChecked(true)
            }

            btn0.iconPainter = func(btn, bc, pos, flags)
            {
                bc.painter.setParams(.Antialiased)
                let color = flags & .Checked ? btn.themeColors().btnIcon_CheckedIcon : btn.themeColors().btnIcon_Icon
                drawShapeGlyph(bc.painter, enumFromUserData'FormShapeKind(btn.userData), pos, color)
            }

            btn0.sigPressed += func|prop = me, layout, type, fieldName|(btn)
            {
                let kind = enumFromUserData'u64(btn.userData)
                prop.pushTypedValue(cast(kind), type, fieldName, true)
                updateBtnState(prop, layout, type, fieldName)
            }
        }

        layout.computeLayout()
    }

    // Opens the list a style cell owns, or closes the one already open.
    //
    // The entries are samples of a stroke, and the current one is said by the mark leading its
    // row rather than by filling it: an accent ground behind a sample that is itself a horizontal
    // line reads as a second, much louder line, and the row stops showing the value it exists to
    // show. Answers null when the call closed the open list rather than opening one.
    mtd createStylePopup(btn: *IconButton, rowHeight, width: f32)->*PopupListCtrl?
    {
        if .stylePopup
        {
            .stylePopup.cancel()
            return null
        }

        let popup = PopupListCtrl.create(cast(*Wnd, btn))
        .stylePopup             = popup
        popup.itemHeight        = rowHeight
        popup.minimumWidth      = width
        popup.fitVertically     = true
        popup.markSelectionOnly = true
        return popup
    }

    // One popup for both line ends: 'begin' selects the beginCap or endCap field
    // and mirrors the sample stroke accordingly.
    mtd createPopupCapStyle(btn: *IconButton, begin: bool)
    {
        let popup = .createStylePopup(btn, PopupCapRowHeight, PopupCapWidth)
        if not popup do
            return

        let fieldName = begin ? #nameof(FormLine.beginCap) : #nameof(FormLine.endCap)

        func selectedCap(prop: *PropWnd, begin: bool)->LineCapStyle
        {
            let type = prop.getSelectedFormType()
            if type != FormLine and type != FormArrow do
                return .None
            let curSel = assume cast(*FormLine, prop.getSelectedBaseForm())
            return begin ? curSel.beginCap : curSel.endCap
        }

        let cur = selectedCap(me, begin)
        for i in LineCapStyle
        {
            let item = popup.addItem("")
            item.userData0      = enumToUserData(i)
            item.contentPainter = func|begin, btn|(item, bc, pos, flags)
            {
                bc.painter.setParams(.Antialiased)
                let cap   = enumFromUserData'LineCapStyle(item.userData0)
                let color = flags & .Hot ? btn.themeColors().popupList_HotText : btn.themeColors().popupList_Text
                drawCapGlyph(bc.painter, cap, begin, pos, color)
            }
        }

        popup.setSelectedIndex(cast(u32, cur))
        popup.sigClosed = func|prop = me, btn, fieldName|(list, idx)
        {
            if idx != Swag.U32.Max
            {
                let cap = enumFromUserData'LineCapStyle(list.items[idx]!.userData0)
                prop.pushTypedValue(cast(u32, cap), FormLine, fieldName, true)
            }

            prop.stylePopup = null
            btn.setChecked(false)
            list.destroy()
        }

        let rect = btn.surfaceRect()
        popup.show(rect.x, rect.bottom(), PopupCapWidth)
    }

    // The dash chooser lists one sample of the stroke per style, marked the way the line ends are:
    // a filled row behind a sample that is itself a dashed line hid the very thing the row shows.
    mtd createPopupDashStyle(btn: *IconButton)
    {
        let popup = .createStylePopup(btn, PopupRowHeight, PopupDashWidth)
        if not popup do
            return

        let curSel = .getSelectedBaseForm()
        var cur    = 0'u32

        // `Pattern` takes its lengths from the pen and has nothing to show on its own.
        for i in DashStyle where i != .Pattern
        {
            if curSel.dashStyle == i do
                cur = cast(u32, popup.items.count)

            let item = popup.addItem("")
            item.userData0      = enumToUserData(i)
            item.contentPainter = func|btn|(item, bc, pos, flags)
            {
                bc.painter.setParams(.Antialiased)
                var rect = pos
                rect.inflate(-DashSize, 0)

                let dash  = enumFromUserData'DashStyle(item.userData0)
                let color = flags & .Hot ? btn.themeColors().popupList_HotText : btn.themeColors().popupList_Text
                var pen   = Pen.createDash(dash, color, DashSize)
                pen.dashBlankScale = 0.25
                bc.painter.drawLine(rect.x, rect.vertCenter(), rect.right(), rect.vertCenter(), pen)
            }
        }

        popup.setSelectedIndex(cur)
        popup.sigClosed = func|prop = me, btn|(list, idx)
        {
            if idx != Swag.U32.Max
            {
                let dash = enumFromUserData'DashStyle(list.items[idx]!.userData0)
                prop.pushTypedValue(cast(u32, dash), BaseForm, #nameof(BaseForm.dashStyle), true, true)
            }

            prop.stylePopup = null
            btn.setChecked(false)
            list.destroy()
        }

        let rect = btn.surfaceRect()
        popup.show(rect.x, rect.bottom(), PopupDashWidth)
    }
}
