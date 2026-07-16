using Core, Pixel

// Editor of a Pixel.FontFamilyStyle field: two toggle buttons (Bold / Italic) writing the
// Regular/Bold/Italic/BoldItalic combination back into the field. Registered as a builtin
// through the editor registry, exactly like the Color and vector editors.
struct FontStyleEditor {}

impl IPropertyEditor for FontStyleEditor
{
    mtd impl canEdit(type: typeinfo)->bool
    {
        return type == FontFamilyStyle
    }

    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: [*] u8, parent: *PropertiesItem)->*PropertiesItem
    {
        parent.flags.add(.NoSeparator | .NoFocus)

        let item  = list.addItem(value, data, parent)
        let style = cast(*FontFamilyStyle) data

        const BtnW = 34
        let lineH  = list.getThemeMetrics().btnPush_Height

        // Grid mode packs the pair left in the value column; the panel/list modes center
        // it as its own full-width row.
        with let line = StackLayoutCtrl.create(item.line, list.isGridLike() ? .HorzFit : .HorzCenter, {0, 0, 0, lineH})
        {
            .anchorStyle = .X
            .spacing     = 4
        }

        with let btnBold = IconButton.create(line, {}, {0, 0, BtnW, lineH})
        {
            .name = "B"
            .setForm(.RoundSquare)
            .iconBtnFlags.add(.Checkable)
        }

        with let btnItalic = IconButton.create(line, {}, {0, 0, BtnW, lineH})
        {
            .name = "I"
            .setForm(.RoundSquare)
            .iconBtnFlags.add(.Checkable)
        }

        func writeStyle(list: *Properties, item: *PropertiesItem, style: *FontFamilyStyle, btnBold, btnItalic: *IconButton)
        {
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

        btnBold.sigCheckChanged += func|list, item, style, btnBold, btnItalic|(btn)
        {
            writeStyle(list, item, style, btnBold, btnItalic)
        }

        btnItalic.sigCheckChanged += func|list, item, style, btnBold, btnItalic|(btn)
        {
            writeStyle(list, item, style, btnBold, btnItalic)
        }

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
