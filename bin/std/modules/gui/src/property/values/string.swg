impl Properties
{
    mtd validateDynamicString(item: *PropertiesItem)
    {
        var data = cast(*String) item.data
        if item.editBox do
            dref data = item.editBox.getText()
        .hasChanged(item)
    }

    mtd constructDynamicString(value: Swag.TypeValue, data: *u8, parentItem: *PropertiesItem)
    {
        let item = .addItem(value, data, parentItem)
        var editWidth = cast(f32) Reflection.getAttributeValue(value, me.EditSize, "size", me.sizeEditValue)
        if !me.isGridLike() do
            editWidth = me.listContentWidthFromUseful(editWidth)
        with let ed = EditBox.create(item.line, dref cast(*String) data)
        {
            .maxSize.x = editWidth
            if me.isGridLike() do
                .dockStyle = .CenterKeepSizeVert
            else
            {
                .anchorStyle = .X
            }
            .sigLoseFocus += func|prop = me, item|(ed) { prop.validateDynamicString(item); }
        }

        me.adaptCondensedControl(ed)
        me.flattenCondensedEdit(ed)
        item.editBox = ed
    }

    mtd constructStaticString(value: Swag.TypeValue, data: *u8, parentItem: *PropertiesItem)
    {
        let item = .addItem(value, data, parentItem)
        var editWidth = cast(f32) Reflection.getAttributeValue(value, me.EditSize, "size", me.sizeEditValue)
        if !me.isGridLike() do
            editWidth = me.listContentWidthFromUseful(editWidth)

        with let ed = EditBox.create(item.line, dref cast(*string) data)
        {
            .maxSize.x = editWidth
            if me.isGridLike() do
                .dockStyle = .CenterKeepSizeVert
            else
            {
                .anchorStyle = .X
            }
            .editBoxFlags = .ReadOnly
        }

        me.adaptCondensedControl(ed)
        me.flattenCondensedEdit(ed)
        item.editBox = ed
    }
}
