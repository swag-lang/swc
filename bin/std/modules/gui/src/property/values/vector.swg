using Core, Core.Math, Pixel

impl Properties
{
    mtd constructVector(value: Swag.TypeValue, typeStruct: const *Swag.TypeInfoStruct, data: [*] u8, parentItem: *PropertiesItem)->*PropertiesItem
    {
        // Custom struct editors keep the container row separator-less, like the inline-struct
        // path in addValue does (the registry path bypasses that, so replicate it here).
        parentItem.flags.add(.NoSeparator | .NoFocus)

        let item = .addItem(value, data, parentItem)
        item.selfPropagate = true       // each component box writes every instance itself
        var width = .position.width
        if !.isGridLike()
        {
            width = cast(f32) Reflection.getAttributeValue(value, .EditSize, "size", .sizeEditValue)
            width = .listContentWidthFromUseful(width)
        }
        let line = Wnd.create'Wnd(item.line, {0, 0, width, .getThemeMetrics().editBox_Height})
        if !.isGridLike() do
            line.maxSize.x = width

        // Grid rows center the field row vertically in the cell; list rows stack it
        // under the name label, capped at the edit width by maxSize (an anchored width
        // would drift with the resize history).
        if .isGridLike() do
            line.dockStyle = .CenterKeepSizeVert

        .adaptCondensedControl(line)

        for v in typeStruct.fields
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
                .sigLoseFocus += func|prop = me, item, fieldOffset|(ed)
                {
                    // Write this component into every edited instance, leaving the others.
                    prop.writeFloatComponent(item, fieldOffset, catch StrConv.toF32(ed.text))
                    prop.hasChanged(item)
                }
            }

            me.flattenCondensedEdit(ed)

            item.sigRefresh += func|prop = me, ed, dataField, fieldOffset|(item)
            {
                ed.setText(Format.toString("%", dref dataField))
                prop.setEditMixedSub(item, ed, fieldOffset, #sizeof(f32))
            }
        }

        return item
    }
}

// The built-in editor for the whole vector family. A single IPropertyEditor whose canEdit
// claims five related types — exactly the family-matching a type-keyed map could not express.
// constructVector only needs the field type's struct layout, which is value.pointedType, so the
// same editor serves them all.
struct VectorEditor {}

impl IPropertyEditor for VectorEditor
{
    mtd impl canEdit(type: typeinfo)->bool
    {
        return type == Math.Vector2 or
               type == Math.Vector3 or
               type == Math.Vector4 or
               type == Math.Point or
               type == Math.Rectangle
    }

    mtd impl construct(list: *Properties, value: Swag.TypeValue, data: [*] u8, parent: *PropertiesItem)->*PropertiesItem
    {
        return list.constructVector(value, cast(const *Swag.TypeInfoStruct) value.pointedType, data, parent)
    }
}

#init
{
    Properties.registerEditor'(VectorEditor)()
}
