#global public
using Core, Pixel

// Building the grid from reflection: addItem creates a single row window; addValue dispatches a
// field to the right editor (the editor registry first, then the built-in kinds); addStructInternal
// walks a struct's fields (handling categories and the notify interface). The refresh side of each
// editor lives with the editor (values/*.swg) and is driven by Properties.refreshItem.
moduleprivate impl Properties
{
    // Create a row for 'value' (field typeinfo + name) bound to 'data' under 'parentItem'.
    // Public so custom editors registered with registerEditor (possibly authored in another
    // module) can build their row the same way the built-in editors do.
    public mtd addItem(value: Swag.TypeValue, data: #null *u8, parentItem: #null *PropertiesItem, height: f32 = 0, flags = AddItemFlags.Name | AddItemFlags.Description)->*PropertiesItem
    {
        var line: *Wnd

        if .isGridLike() do
            line = Wnd.create'Wnd(.edView, {0, 0, .position.width, height orelse .gridLineHeight})
        else
        {
            let stk = StackLayoutCtrl.create(.edView, .Top, {0, 0, .position.width, height orelse .gridLineHeight})
            stk.fitToContent = true
            line             = stk
        }

        with line
        {
            .wndFlags.add(.PreChildsPaint)

            // Lines never take the keyboard focus themselves: navigation lives on
            // the edView and edition on the row editors. This keeps a click on a
            // row label from stealing focus away from the navigation surface.
            .focusStrategy = .None

            if me.isGridLike()
            {
                .margin.z = me.rightMargin
                .margin.y = me.gridLineMargin * 0.5
                .margin.w = me.gridLineMargin * 0.5
            }
            else do
                me.setListContentPadding(line)
        }

        with let item = me.items.addNewPtr()
        {
            .line      = line
            .type      = value.pointedType
            .typeValue = value
            .data      = data
            .parent    = parentItem
            .level     = parentItem ? parentItem.level + 1 : 0
            .section   = parentItem ? parentItem.section : 0
            .valueCellHeight = height orelse me.gridLineHeight
            if me.isGridLike() do
                .extendFocus = me.gridLineMargin * 0.5
        }

        let prop = me
        line.hookOnEvent = func|prop, item|(wnd, evt) { return prop.onItemEvent(item, wnd, evt); }

        // Name
        if flags.has(.Name)
        {
            var dispName: String

            let attrName = Reflection.getAttributeValue(value, Properties.Name, "name")
            if attrName != null do
                dispName = cast(string) attrName
            else do
                dispName = Utf8.beautifyName(value.name)

            if !dispName.isEmpty()
            {
                var labelWidth = cast(f32) me.gridColumnSize
                if !me.isGridLike() do
                    labelWidth = me.listContentWidth()
                with let label = Label.create(line, dispName, {0, 0, labelWidth, item.line.position.height})
                {
                    if me.isGridLike()
                    {
                        .vertAlignmentText = .Center
                        .horzAlignmentText = .Left
                        .dockStyle         = .Left
                        .margin.z          = me.gridMarginColumn
                        .paddingText.x     = me.leftMargin
                    }
                    else
                    {
                        .labelFlags |= .WordWrap | .AutoHeight | .DontAdaptSingleLineHeight
                        .vertAlignmentText = .Top
                        .horzAlignmentText = .Left
                        .margin.y          = me.listNameMarginBefore
                        .margin.w          = me.listNameMarginAfter
                    }

                    .style.setFont(me.fontName)
                }

                item.label = label
                if parentItem
                {
                    item.filter += " "
                    item.filter = parentItem.filter
                    item.filter += " "
                }

                item.filter += dispName
            }
        }

        // Description
        let dispDesc = Reflection.getAttributeValue(value, Properties.Description, "desc")
        if dispDesc != null
        {
            item.filter += " "
            item.filter += cast(string) dispDesc
            item.description = cast(string) dispDesc

            if flags.has(.Description)
            {
                if !.isGridLike()
                {
                    with let labelDesc = Label.create(line, "", {0, 0, me.listContentWidth(), 0})
                    {
                        .labelFlags |= .WordWrap | .AutoHeight | .DontAdaptSingleLineHeight
                        .vertAlignmentText = .Top
                        .horzAlignmentText = .Left
                        .margin.w          = me.listDescMarginAfter
                        .setText(cast(string) dispDesc)
                        item.labelDesc = labelDesc
                    }
                }
            }
        }

        return item
    }

    mtd addValue(value: Swag.TypeValue, data: [*] u8, parentItem: *PropertiesItem)
    {
        // The editor registry is the single dispatch for custom representations: the built-in
        // struct editors (Color, the vector family) register here too, and a later registration
        // for the same type overrides them. The matched editor wires its own item.sigRefresh,
        // which refreshItem then drives.
        let reg = findEditor(value.pointedType)
        if reg
        {
            let item = reg.itf.construct(me, value, data, parentItem)
            Debug.assert(item != null)
            item.sigRefresh.call(item)
            return
        }

        // Value
        switch
        {
        case Reflection.isStaticArray(value.pointedType):
            let item           = .addItem(value, data, parentItem)
            let typeArr        = cast(const *Swag.TypeInfoArray) value.pointedType
            let numItemsBefore = .items.count

            var newData = data
            for i in typeArr.count
            {
                var subValue: Swag.TypeValue
                subValue.name        = Format.toString("%", i).toString()
                subValue.pointedType = typeArr.pointedType
                .addValue(subValue, newData, item)
                newData += typeArr.pointedType.sizeof
            }

            item.numChilds += cast(u32) (.items.count - numItemsBefore)

        case Reflection.isEnum(value.pointedType):
            let typeEnum = cast(const *Swag.TypeInfoEnum) value.pointedType
            .constructEnum(value, typeEnum, data, parentItem)

        case value.pointedType == Core.String:
            .constructDynamicString(value, data, parentItem)

        case Reflection.isString(value.pointedType):
            .constructStaticString(value, data, parentItem)

        case Reflection.isBool(value.pointedType):
            .constructBool(value, data, parentItem)

        case Reflection.isInteger(value.pointedType) or Reflection.isFloat(value.pointedType):
            let typeNative = cast(const *Swag.TypeInfoNative) value.pointedType
            .constructNative(value, typeNative, data, parentItem)

        case value.pointedType == Array:
            .constructArray(value, data, parentItem)

        case Reflection.isStruct(value.pointedType):
            let typeSubStruct = cast(const *Swag.TypeInfoStruct) value.pointedType
            if typeSubStruct.fromGeneric == Array
            {
                .constructArray(value, data, parentItem)
                break
            }

            // A plain (non-registered) struct expands inline into one row per field. Custom
            // struct editors (Color, the vector family, ...) are handled by the editor registry
            // at the top of this method and never reach here.
            parentItem.flags.add(.NoSeparator | .NoFocus)
            let item           = .addItem(value, data, parentItem)
            let numItemsBefore = .items.count
            .addStructInternal(typeSubStruct, data, item)
            item.numChilds = cast(u32) (.items.count - numItemsBefore)
        }
    }

    mtd addStructInternal(typeStruct: const *Swag.TypeInfoStruct, addr: [*] u8, parentItem: *PropertiesItem)
    {
        var newParent = parentItem

        // If the struct has implemented the notify interface, store it
        if parentItem do
            parentItem.ntfyItf = @mkinterface(addr, typeStruct, IPropertyNotify)

        var categItem: *PropertiesItem
        foreach value in typeStruct.fields
        {
            // Category
            let subCateg = Reflection.getAttributeValue(value, Properties.Category, "name")
            if subCateg != null
            {
                let v:   Swag.TypeValue{name: cast(string) subCateg}
                let item = .addItem(v, null, parentItem)
                item.label.style.setFont(&.fontCategory)
                item.flags.add(.Category | .NoSeparator | .Expanded | .NoFocus)
                item.level = 0
                .sections.add({item, 1})
                newParent = item
                categItem = item
            }

            let numItemsBefore = .items.count
            .addValue(value, addr + value.offset, newParent)
            if categItem do
                categItem.numChilds += cast(u32) (.items.count - numItemsBefore)
        }
    }
}
