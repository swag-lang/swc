using Core, Pixel

// Editor of a Pixel.FontFamilyStyle field: two toggle buttons (Bold / Italic) writing the
// Regular/Bold/Italic/BoldItalic combination back into the field. Registered as a builtin
// through the editor registry, exactly like the Color and vector editors.
internal struct FontStyleEditor {}

internal impl IPropertyEditor for FontStyleEditor
{
    mtd impl canEdit(type: typeinfo?)->bool
    {
        return type == FontFamilyStyle
    }

    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: [*] u8?, parent: *PropertiesItem?)->*PropertiesItem
    {
        let parentItem = parent!
        parentItem.flags.add(.NoSeparator | .NoFocus)

        let item  = list.addItem(value, data, parentItem)
        let style = cast(*FontFamilyStyle?) data

        const BtnW = 34
        let lineH = list.themeMetrics().btnPush_Height

        // Grid mode packs the pair left in the value column; the panel/list modes center
        // it as its own full-width row.
        with let line = StackLayoutCtrl.create(item.line, list.isGridLike() ? .HorizontalFit : .HorizontalCenter, {0, 0, 0, lineH})
        {
            .anchorStyle = .Right
            .spacing     = 4
        }

        // Toggle, not Radio: bold/italic are independent on/off switches, so a
        // click on a checked button must uncheck it (Radio remains checked).
        //
        // A switch that is on says so in the accent it is lettered in. The rule a tool rail
        // marks its picked tool with would run under a field of the form here, which reads
        // as an underlined row rather than as one letter being on.
        with let btnBold = IconButton.create(line, {}, {0, 0, BtnW, lineH})
        {
            .name = "B"
            .setForm(.RoundedRectangle)
            .updateFlags(.Toggle)
            .setCheckIndicator(.Ink)
        }

        with let btnItalic = IconButton.create(line, {}, {0, 0, BtnW, lineH})
        {
            .name = "I"
            .setForm(.RoundedRectangle)
            .updateFlags(.Toggle)
            .setCheckIndicator(.Ink)
        }

        func writeStyle(list: *Properties, item: *PropertiesItem, style: *FontFamilyStyle?, btnBold, btnItalic: *IconButton)
        {
            if style == null do
                return
            let bold   = btnBold.isChecked
            let italic = btnItalic.isChecked
            if bold and italic do
                style[] = .BoldItalic
            elif bold do
                style[] = .Bold
            elif italic do
                style[] = .Italic
            else do
                style[] = .Regular
            list.commitItemChange(item)
        }

        btnBold.sigCheckedChanged += func|list, item, style, btnBold, btnItalic|(btn) { writeStyle(list, item, style, btnBold, btnItalic) }

        btnItalic.sigCheckedChanged += func|list, item, style, btnBold, btnItalic|(btn) { writeStyle(list, item, style, btnBold, btnItalic) }

        item.sigRefresh += func|style, btnBold, btnItalic|(item)
        {
            let s = style![]
            btnBold.setChecked(s == .Bold or s == .BoldItalic)
            btnItalic.setChecked(s == .Italic or s == .BoldItalic)
        }

        item.sigRefresh.call(item)
        return item
    }
}

#init
{
    Properties.registerEditor'(FontStyleEditor)()
}
