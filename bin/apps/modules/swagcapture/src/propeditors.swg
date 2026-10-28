// Swag Capture-specific property editors, plugged into the std Properties editor registry:
// the generated panel builds these rows like any other field, undo included.

// Editor of a FormTextAlign field: one labelled row of three segments, the alignment words. The
// same editor serves the horizontal and the vertical alignment; the field name selects the words.
struct AlignEditor {}

impl IPropertyEditor for AlignEditor
{
    mtd impl canEdit(type: typeinfo?)->bool => type == FormTextAlign

    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: [*] u8?, parent: *PropertiesItem?)->*PropertiesItem
    {
        let item  = list.addItem(value, data, parent)
        let align = cast(*FormTextAlign, unwrap data)
        let vert  = value.name == #nameof(FormText.alignVert)

        var combo: *ComboBox?
        if list.kind == .Panel
        {
            if item.label != null do
                item.label.hide()
            with let ctrl = ComboCtrl.create(item.line, Properties.itemDisplayName(value).toString())
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
                .dockStyle = .CenterKeepSizeVert
            }
        }

        // One segment per FormTextAlign value, in visual order (left/top, center, right/bottom).
        const Values = [FormTextAlign.LeftTop, FormTextAlign.Center, FormTextAlign.RightBottom]
        let combon: *ComboBox = combo
        combon.updateFlags(.Segmented)
        let texts = appStrings()
        combon.addItem(vert ? texts.act_AlignTop : texts.act_AlignLeft)
        combon.addItem(vert ? texts.act_AlignMiddle : texts.act_AlignCenter)
        combon.addItem(vert ? texts.act_AlignBottom : texts.act_AlignRight)

        combon.sigChanged += func|list, item, align|(_, index)
        {
            if index >= 3 do
                return
            align[] = Values[index]
            list.commitItemChange(item)
        }

        item.sigRefresh += func|align, combon|(_)
        {
            for v, i in Values where align[] == v do
                combon.setSelectedIndex(cast(u32, i), notify: false)
        }

        item.sigRefresh.call(item)
        return item
    }
}

#init
{
    Properties.registerEditor'(AlignEditor)()
}
