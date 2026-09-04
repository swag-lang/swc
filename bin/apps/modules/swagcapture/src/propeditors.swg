// Swag Capture-specific property editors, plugged into the std Properties editor registry:
// the generated panel builds these rows like any other field, undo included.

// Builds one alignment toggle of an [[AlignEditor]] row.
//
// `index` selects the alignment in visual order, which is also the offset from the first
// toolbar icon of the horizontal or vertical family.
private func createAlignButton(line: *Wnd, vert: bool, width, height: f32, index: s32)->*IconButton
{
    const Labels = ["L", "C", "R"]

    with let btn = IconButton.create(line, {}, {0, 0, width, height})
    {
        .setForm(.Rectangle)
        .updateFlags(.Radio)

        // The picked alignment is already the one glyph in the accent, and three
        // rules under a row of three buttons underline the row rather than mark
        // one of them. The rail belongs to a tool rail, not to a field.
        .setCheckIndicator(.Ink)

        // The Swag Capture toolbar icons when the app is there, letter fallbacks otherwise
        // (the headless fixtures build panels without a full application).
        if g_Main
        {
            let base = vert ? CaptureIcons.AlignTop : CaptureIcons.TextAlignLeft
            .setIcon(g_Main!.icon(cast(CaptureIcons) (cast(s32) base + index)))
        }
        else do
            .name = Labels[index]
    }

    return btn
}

// Editor of a FormTextAlign field: three exclusive toggle buttons. The same editor
// serves the horizontal and the vertical alignment; the field name selects the icons.
struct AlignEditor {}

impl IPropertyEditor for AlignEditor
{
    mtd impl canEdit(type: typeinfo)->bool
    {
        return type == FormTextAlign
    }

    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: [*] u8, parent: *PropertiesItem)->*PropertiesItem
    {
        parent.flags.add(.NoSeparator | .NoFocus)

        let item  = list.addItem(value, data, parent)
        let align = cast(*FormTextAlign) data
        let vert  = value.name == #nameof(FormText.alignVert)

        const BtnW = 34
        let lineH = list.themeMetrics().btnPush_Height

        // Centered as its own full-width row in the panel; packed left in a grid cell.
        with let line = StackLayoutCtrl.create(item.line!, list.isGridLike() ? .HorizontalFit : .HorizontalCenter, {0, 0, 0, lineH})
        {
            .anchorStyle = .Right
            .spacing     = 4
        }

        // One button per FormTextAlign value, in visual order (left/top, center, right/bottom)
        const Values = [FormTextAlign.LeftTop, FormTextAlign.Center, FormTextAlign.RightBottom]

        // The row names its three buttons, so the array is built from them rather than
        // filled afterwards: every slot holds a window from the moment it exists.
        let btns = [createAlignButton(line, vert, BtnW, lineH, 0),
                    createAlignButton(line, vert, BtnW, lineH, 1),
                    createAlignButton(line, vert, BtnW, lineH, 2)]

        for i in 3
        {
            btns[i].sigCheckedChanged += func|list, item, align, i|(btn)
            {
                if !btn.isChecked
                {
                    // The selected alignment cannot be untoggled, only replaced
                    btn.setChecked(align[] == Values[i])
                    return
                }

                align[] = Values[i]
                list.commitItemChange(item)
            }
        }

        item.sigRefresh += func|align, btns|(item)
        {
            for i in 3
            {
                btns[i].setChecked(align[] == Values[i])
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
