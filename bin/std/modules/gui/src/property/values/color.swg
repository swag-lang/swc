using Core, Pixel

impl Properties
{
    mtd constructColor(value: Swag.TypeValue, data: [*] u8, parentItem: *PropertiesItem)->*PropertiesItem
    {
        let item  = .addItem(value, data, parentItem)
        let color = cast(*Color) data

        let opaque    = Reflection.hasAttribute(value, .Opaque)
        let keepAlpha = Reflection.hasAttribute(value, .KeepAlpha)
        let editAlpha = !opaque and !keepAlpha

        let width       = cast() Reflection.getAttributeValue(value, .EditSize, "size", .sizeEditValue)
        const MarginBtn = 4
        const WidthBtn  = 60
        let prop        = me

        // Match the other value editors: fill the value column in grid mode, but
        // stay left-aligned at its edit size in list mode (otherwise the color row
        // is the only one that ends up centered).
        let line = Wnd.create'Wnd(item.line, {0, 0, width, .getThemeMetrics().editBox_Height})
        line.maxSize.x = width
        if .kind == .Grid do
            line.dockStyle = .CenterKeepSizeVert
        else do
            line.anchorStyle = .X

        with let btn = IconButton.create(line, {}, {0, 0, WidthBtn, item.line.position.height})
        {
            .dockStyle   = .Left
            .arrowPos    = .RightDown
            .checkedForm = .None
            .setForm(.RoundSquare)
            .iconBtnFlags.add(.Popup | .CheckableToggle)
        }

        with let ed = EditBox.create(line, "", {0, 0, width - MarginBtn - WidthBtn, item.line.position.height})
        {
            .dockStyle = .Center
            .margin.x  = MarginBtn
            .setInputX64(0, opaque ? 0xFFFFFF : 0xFFFFFFFF)
            .sigLoseFocus += func|prop, color, item, opaque, keepAlpha|(ed)
            {
                var result = cast(u32) (catch StrConv.parseX64(ed.text).value & 0xFFFFFFFF)
                if opaque do
                    result |= 0xFF000000
                elif keepAlpha do
                    result |= color.a << 24
                color.argb = result
                prop.hasChanged(item)
            }
        }

        btn.sigPaintIcon = func|color|(btn, bc, pos, paintFlags)
        {
            bc.painter.setParams(.Antialiased)
            if !color.isOpaque() do
                bc.painter.fillRoundRect(pos, 5, 5, Brush.createHatch(.CheckBoardLarge, Argb.DarkGray))
            bc.painter.fillRoundRect(pos, 5, 5, dref color)
        }

        btn.sigShowPopup += func|prop, color, item, opaque, keepAlpha|(btn)
        {
            if !btn do
                return
            let frame = btn.createAnchorPopup(356, 382)
            prop.editPopup = frame

            var pal: Array'Color
            for i in 9 do
                pal.add(Color.getBlendKeepAlpha(Argb.White, Argb.Black, i / 8.0))

            var flags = ColorPickerFlags.All
            if opaque or keepAlpha do
                flags.remove(ColorPickerFlags.Alpha)

            let picker = ColorPickerCtrl.createWithPalette(frame, {8, 54}, pal, flags)
            picker.setColor(color)
            picker.sigChanged += func|prop, color, item, opaque, keepAlpha|(pk)
            {
                var result = pk.getColor().argb
                if opaque do
                    result |= 0xFF000000
                elif keepAlpha do
                    result |= color.a << 24
                color.argb = result
                prop.hasChanged(item)
            }
        }

        btn.sigHidePopup += func|prop|(btn)
        {
            prop.editPopup = null
        }

        item.sigRefresh += func|ed, btn, color, editAlpha|(item)
        {
            if editAlpha do
                ed.setText(Format.toString("%{X08}", color.argb))
            else do
                ed.setText(Format.toString("%{X06}", color.argb & 0xFFFFFF))
            btn.invalidate()
        }

        return item
    }
}

public impl IPropertyValue for Color
{
    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: [*] u8, parent: *PropertiesItem)->*PropertiesItem
    {
        return list.constructColor(value, data, parent)
    }
}
