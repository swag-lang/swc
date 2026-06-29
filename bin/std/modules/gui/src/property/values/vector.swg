using Core, Core.Math, Pixel

impl Properties
{
    mtd constructVector(value: Swag.TypeValue, typeStruct: const *Swag.TypeInfoStruct, data: [*] u8, parentItem: *PropertiesItem)->*PropertiesItem
    {
        let item = .addItem(value, data, parentItem)
        item.selfPropagate = true       // each component box writes every instance itself
        let line = Wnd.create'Wnd(item.line, {0, 0, .position.width, .getThemeMetrics().editBox_Height})
        let prop = me

        // Grid rows center the field row vertically in the cell; list rows stack it
        // under the name label (the row is a StackLayoutCtrl), where dock-centering
        // would overlap the label — anchor the width and let the stack place it.
        if .isGridLike() do
            line.dockStyle = .CenterKeepSizeVert
        else do
            line.anchorStyle = .X

        .adaptCondensedControl(line)

        foreach v in typeStruct.fields
        {
            let dataField   = cast(*f32) (data + v.offset)
            let fieldOffset = cast(u64) v.offset

            with let label = Label.create(line, v.name[0 to 0], {0, 0, item.line.position.height})
            {
                .dockStyle         = .Left
                .horzAlignmentText = .Center
            }

            with let ed = EditBox.create(line, "", {0, 0, item.line.position.height * 2})
            {
                .dockStyle = .Left
                .setInputF64()
                .sigLoseFocus += func|prop, item, fieldOffset|(ed)
                {
                    // Write this component into every edited instance, leaving the others.
                    prop.writeFloatComponent(item, fieldOffset, catch StrConv.toF32(ed.text))
                    prop.hasChanged(item)
                }
            }

            me.flattenCondensedEdit(ed)

            item.sigRefresh += func|prop, ed, dataField, fieldOffset|(item)
            {
                ed.setText(Format.toString("%", dref dataField))
                prop.setEditMixedSub(item, ed, fieldOffset, #sizeof(f32))
            }
        }

        return item
    }
}

public impl IPropertyValue for Math.Vector2
{
    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: [*] u8, parent: *PropertiesItem)->*PropertiesItem
    {
        return list.constructVector(value, Math.Vector2, data, parent)
    }
}

public impl IPropertyValue for Math.Vector3
{
    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: [*] u8, parent: *PropertiesItem)->*PropertiesItem
    {
        return list.constructVector(value, Math.Vector3, data, parent)
    }
}

public impl IPropertyValue for Math.Vector4
{
    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: [*] u8, parent: *PropertiesItem)->*PropertiesItem
    {
        return list.constructVector(value, Math.Vector4, data, parent)
    }
}

public impl IPropertyValue for Math.Point
{
    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: [*] u8, parent: *PropertiesItem)->*PropertiesItem
    {
        return list.constructVector(value, Math.Point, data, parent)
    }
}

public impl IPropertyValue for Math.Rectangle
{
    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: [*] u8, parent: *PropertiesItem)->*PropertiesItem
    {
        return list.constructVector(value, Math.Rectangle, data, parent)
    }
}
