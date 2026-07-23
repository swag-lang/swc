using Core, Pixel

// Editor of a Pixel.FontFamilyStyle field: two toggle buttons (Bold / Italic) writing the
// Regular/Bold/Italic/BoldItalic combination back into the field. Registered as a builtin
// through the editor registry, exactly like the Color and vector editors.
struct FontStyleEditor {}

impl IPropertyEditor for FontStyleEditor
{
    mtd impl canEdit(type: #null typeinfo)->bool
    {
        return type == FontFamilyStyle
    }

    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: #null [*] u8, parent: #null *PropertiesItem)->*PropertiesItem
    {
        let parentItem = notnull parent
        parentItem.flags.add(.NoSeparator | .NoFocus)

        let item  = list.addItem(value, data, parentItem)
        let style = cast(#null *FontFamilyStyle) data

        const BtnW = 34
        let lineH  = list.getThemeMetrics().btnPush_Height

        // Grid mode packs the pair left in the value column; the panel/list modes center
        // it as its own full-width row.
        with let line = StackLayoutCtrl.create(item.line, list.isGridLike() ? .HorzFit : .HorzCenter, {0, 0, 0, lineH})
        {
            .anchorStyle = .X
            .spacing     = 4
        }

        // CheckableToggle, not Checkable: bold/italic are independent on/off switches, so a
        // click on a checked button must uncheck it (Checkable ignores clicks when checked).
        with let btnBold = IconButton.create(line, {}, {0, 0, BtnW, lineH})
        {
            .name = "B"
            .setForm(.RoundSquare)
            .iconBtnFlags.add(.CheckableToggle)
        }

        with let btnItalic = IconButton.create(line, {}, {0, 0, BtnW, lineH})
        {
            .name = "I"
            .setForm(.RoundSquare)
            .iconBtnFlags.add(.CheckableToggle)
        }

        func writeStyle(list: *Properties, item: *PropertiesItem, style: #null *FontFamilyStyle, btnBold, btnItalic: *IconButton)
        {
            if style == null do
                return
            let bold   = btnBold.isChecked
            let italic = btnItalic.isChecked
            if bold and italic do
                dref style = .BoldItalic
            elif bold do
                dref style = .Bold
            elif italic do
                dref style = .Italic
            else do
                dref style = .Regular
            list.hasChanged(item)
        }

        btnBold.sigCheckChanged += func|list, item, style, btnBold, btnItalic|(btn) { writeStyle(list, item, style, btnBold, btnItalic) }

        btnItalic.sigCheckChanged += func|list, item, style, btnBold, btnItalic|(btn) { writeStyle(list, item, style, btnBold, btnItalic) }

        item.sigRefresh += func|style, btnBold, btnItalic|(item)
        {
            let s = dref style
            btnBold.isChecked   = s == .Bold or s == .BoldItalic
            btnItalic.isChecked = s == .Italic or s == .BoldItalic
            btnBold.invalidate()
            btnItalic.invalidate()
        }

        item.sigRefresh.call(item)
        return item
    }
}

#init
{
    Properties.registerEditor'(FontStyleEditor)()
}
