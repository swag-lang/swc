impl Properties
{
    func setDescEditBox(item: *PropertiesItem)
    {
        let arrData = cast(*Array'u8) item.data
        item.editBox.setText(Format.toString("% elements", arrData.count))
    }

    mtd reconstructArray(item: *PropertiesItem)
    {
        let valueType        = assume Reflection.getStructArrayType(item.type)
        let arrData          = cast(*Array'u8) item.data
        let countItemsBefore = .items.count
        let itemIdx          = Slice.findLinear(.items.toSlice(), item)
        let insertItemIdx    = itemIdx + item.numChilds + 1

        // Reconstruct all items (add the end)
        var newData = arrData.buffer
        for i in arrData.count
        {
            var subValue: Swag.TypeValue
            subValue.name        = Format.toString("%", i).toString()
            subValue.pointedType = valueType
            .addValue(subValue, newData, item)
            newData += valueType.sizeof
        }

        // Move all newly reconstructed items at the right place
        let numAddedChilds = cast(u32) (.items.count - countItemsBefore)
        for i in numAddedChilds
        {
            .items.insertAt(insertItemIdx + i, .items[.items.count - numAddedChilds + i])
            .edView.childs.insertAt(insertItemIdx + i, .edView.childs[.edView.childs.count - numAddedChilds + i])
        }

        .items.count -= numAddedChilds
        .edView.childs.count -= numAddedChilds

        // Remove all old items and childs
        for i in item.numChilds
        {
            .items.deletePtr(.items[itemIdx + 1])
            .items.removeAtOrdered(itemIdx + 1)
            .edView.childs[itemIdx + 1].destroyNow()
        }

        // Update state of all newly added items
        item.numChilds = numAddedChilds
        for i in item.numChilds do
            .updateItemState(.items[itemIdx + i + 1])
    }

    mtd refreshArray(item: *PropertiesItem)
    {
        let arrData = cast(*Array'u8) item.data
        if arrData.count == cast(u64) item.userData0 do
            return
        item.userData0 = cast(*void) arrData.count

        .reconstructArray(item)
        setDescEditBox(item)
        .edView.sendResizeEvent()
    }

    mtd clearArray(item: *PropertiesItem)
    {
        let valueType = assume Reflection.getStructArrayType(item.type)
        Reflection.clearStructArray(item.data, valueType)
        .refreshArray(item)
        .hasChanged(item)
    }

    // True when 'item' wraps an array value: a fixed-size [N]T or a dynamic Core.Array.
    mtd isArrayItem(item: *PropertiesItem)->bool
    {
        return item.type and (Reflection.isStaticArray(item.type) or Reflection.isStructArray(item.type))
    }

    // Buffer base, element type and element count of an array item (static or dynamic).
    mtd arrayElementInfo(arrayItem: *PropertiesItem)->{ base: [*] u8, valueType: typeinfo, count: u64 }
    {
        if Reflection.isStructArray(arrayItem.type)
        {
            let vt  = assume Reflection.getStructArrayType(arrayItem.type)
            let arr = cast(*Array'u8) arrayItem.data
            return {arr.buffer, vt, arr.count}
        }

        let typeArr = cast(const *Swag.TypeInfoArray) arrayItem.type
        return {cast([*] u8) arrayItem.data, typeArr.pointedType, typeArr.count}
    }

    // Ordinal of an array element among the array's direct children. Robust for struct arrays,
    // whose element rows are interleaved with their field rows in the flat item list.
    mtd arrayElementIndex(elemItem: *PropertiesItem)->u64
    {
        var idx = 0'u64
        foreach it in .items
        {
            if it == elemItem do
                break
            if it.parent == elemItem.parent do
                idx += 1
        }
        return idx
    }

    // Resolve the array element row (a direct child of an array) from the clicked item or one
    // of its ancestors, so right-clicking a struct element's field still targets the element.
    mtd resolveArrayElement(item: *PropertiesItem)->#null *PropertiesItem
    {
        var scan = cast(#null *PropertiesItem) item
        while scan and scan.parent
        {
            if .isArrayItem(scan.parent) do
                return scan
            scan = scan.parent
        }
        return null
    }

    // Reorder an array element by one slot (dir = -1 up, +1 down). Allowed for both static and
    // dynamic arrays — a reorder never changes the element count.
    mtd moveArrayValue(elemItem: *PropertiesItem, dir: s32)
    {
        let arrayItem = elemItem.parent
        let info      = .arrayElementInfo(arrayItem)
        let idx       = .arrayElementIndex(elemItem)
        let target    = cast(s64) idx + dir
        if target < 0 or target >= cast(s64) info.count do
            return

        Reflection.swapValues(info.base, info.valueType, idx, cast(u64) target)
        .hasChanged(arrayItem)
    }

    mtd removeArrayValue(item: *PropertiesItem)
    {
        let parentItem = item.parent
        let valueType  = assume Reflection.getStructArrayType(parentItem.type)
        let removeIdx  = .arrayElementIndex(item)

        Reflection.removeValueStructArray(parentItem.data, valueType, removeIdx)

        .refreshArray(parentItem)
        .hasChanged(parentItem)
    }

    mtd appendArrayValue(item: *PropertiesItem)
    {
        let valueType = assume Reflection.getStructArrayType(item.type)

        discard Reflection.appendValueStructArray(item.data, valueType)

        .refreshArray(item)
        .hasChanged(item)
    }

    mtd constructArray(value: Swag.TypeValue, data: *u8, parentItem: *PropertiesItem)
    {
        let item           = .addItem(value, data, parentItem)
        let numItemsBefore = .items.count
        item.flags.add(.NoSeparator)

        let valueType = assume Reflection.getStructArrayType(item.type)
        let arrData   = cast(*Array'u8) data
        var newData   = arrData.buffer

        item.userData0 = cast(*void) arrData.count

        for i in arrData.count
        {
            var subValue: Swag.TypeValue
            subValue.name        = Format.toString("%", i).toString()
            subValue.pointedType = valueType
            .addValue(subValue, newData, item)
            newData += valueType.sizeof
        }

        let parentForBtn = .isGridLike() ? item.line : cast(*Wnd) item.label
        let addBtn       = IconButton.create(parentForBtn, .getTheme().getIcon24(ThemeIcons24.Plus, 20), {0, 0, 24, 24})
        addBtn.dockStyle = .isGridLike() ? .Right : .None
        addBtn.setForm(IconButtonForm.Round)
        item.arrayAddButton = addBtn
        if !.isGridLike() do
            item.label.wndFlags.remove(.ClipChildren)
        addBtn.sigPressed += func|prop = me, item|(btn)
        {
            prop.appendArrayValue(item)
        }

        with item.editBox = EditBox.create(item.line, "")
        {
            // Grid rows dock the read-only count field to the left of the cell; list
            // rows stack it under the name label (the row is a StackLayoutCtrl), where
            // docking would overlap the label — anchor the width instead.
            if me.isGridLike() do
                .dockStyle = .Left
            else
            {
                .anchorStyle = .X
            }
            .setForm(.Transparent)
            .enable(false)
        }

        setDescEditBox(item)
        item.numChilds += cast(u32) (.items.count - numItemsBefore)
    }
}
