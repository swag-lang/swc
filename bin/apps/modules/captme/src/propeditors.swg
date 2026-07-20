// Captme-specific property editors, plugged into the std Properties editor registry:
// the generated panel builds these rows like any other field, undo included.

// Editor of a FormTextAlign field: three exclusive toggle buttons. The same editor
// serves the horizontal and the vertical alignment; the field name selects the icons.
struct AlignEditor {}

impl IPropertyEditor for AlignEditor
{
    mtd impl canEdit(type: #nonull typeinfo)->bool
    {
        return type == FormTextAlign
    }

    mtd impl construct(list: #nonull *Properties, value: Swag.TypeValue, data: #nonull [*] u8, parent: #nonull *PropertiesItem)->#nonull *PropertiesItem
    {
        parent.flags.add(.NoSeparator | .NoFocus)

        let item  = list.addItem(value, data, parent)
        let align = cast(#nonull *FormTextAlign) data
        let vert  = value.name == #nameof(FormText.alignVert)

        const BtnW = 34
        let lineH  = list.getThemeMetrics().btnPush_Height

        // Centered as its own full-width row in the panel; packed left in a grid cell.
        with let line = StackLayoutCtrl.create(assume item.line, list.isGridLike() ? .HorzFit : .HorzCenter, {0, 0, 0, lineH})
        {
            .anchorStyle = .X
            .spacing     = 4
        }

        // One button per FormTextAlign value, in visual order (left/top, center, right/bottom)
        const Values = [FormTextAlign.LeftTop, FormTextAlign.Center, FormTextAlign.RightBottom]
        const Labels = ["L", "C", "R"]

        var btns: [3] #nonull *IconButton = undefined
        for i in 3
        {
            with let btn = IconButton.create(line, {}, {0, 0, BtnW, lineH})
            {
                .setForm(.RoundSquare)
                .iconBtnFlags.add(.Checkable)

                // The captme toolbar icons when the app is there, letter fallbacks otherwise
                // (the headless fixtures build panels without a full application).
                if g_Main do
                    .icon = Icon.from(&g_Main.icons24, cast(s32) ((vert ? 11 : 8) + i))
                else do
                    .name = Labels[i]
            }

            btns[i] = btn
        }

        for i in 3
        {
            btns[i].sigCheckChanged += func|list, item, align, i|(btn)
            {
                if !btn.isChecked
                {
                    // The selected alignment cannot be untoggled, only replaced
                    btn.isChecked = dref align == Values[i]
                    btn.invalidate()
                    return
                }

                dref align = Values[i]
                list.hasChanged(item)
            }
        }

        item.sigRefresh += func|align, btns|(item)
        {
            for i in 3
            {
                btns[i].isChecked = dref align == Values[i]
                btns[i].invalidate()
            }
        }

        item.sigRefresh.call(item)
        return item
    }
}

#init
{
    Properties.registerEditor'(AlignEditor)()
}
