using Core, Pixel

// Editor of a Pixel.FontFamilyStyle field: the four styles side by side as segments, each one
// lettered "Aa" in the style it stands for, so the choice is read before it is made. Registered
// as a builtin through the editor registry, exactly like the Color and vector editors.
internal struct FontStyleEditor {}

// The words each segment of a font style is lettered with, in its own style.
internal const FontStyleSample = "Aa"

internal impl IPropertyEditor for FontStyleEditor
{
    mtd impl canEdit(type: typeinfo?)->bool => type == FontFamilyStyle

    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: [*] u8?, parent: *PropertiesItem?)->*PropertiesItem
    {
        let item  = list.addItem(value, data, parent)
        let style = cast(*FontFamilyStyle?, data)

        var combo: *ComboBox?
        if list.kind == .Panel
        {
            if item.label != null do
                item.label.hide()
            with let ctrl = ComboCtrl.create(item.line, itemDisplayName(value).toString())
            {
                .anchorStyle = .Right
                .setLayoutMetrics(.labelWidth, 0)
            }

            combo = ctrl.combo
        }
        else
        {
            with combo = ComboBox.create(item.line)
            {
                .maxSize.x = list.editorWidth
                if list.isGridLike() do
                    .dockStyle = .CenterKeepSizeVert
                else do
                    .preferredSize.x = list.editorWidth
            }
        }

        let combon: *ComboBox = combo
        combon.updateFlags(.Segmented)
        item.assignComboBox(combon)
        for s in [FontFamilyStyle.Regular, FontFamilyStyle.Bold, FontFamilyStyle.Italic, FontFamilyStyle.BoldItalic] do
            combon.addItem(FontStyleSample).fontStyle = s

        combon.sigChanged += func|list, item, style|(_, index)
        {
            if not style or index > cast(u32, FontFamilyStyle.BoldItalic) do
                return
            style[] = cast(FontFamilyStyle, index)
            list.commitItemChange(item)
        }

        item.sigRefresh += func|style, combon|(_)
        {
            if style do
                combon.setSelectedIndex(cast(u32, style[]), notify: false)
        }

        item.sigRefresh.call(item)
        return item
    }
}

#init
{
    Properties.registerEditor'(FontStyleEditor)()
}
