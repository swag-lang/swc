#global public
using Core, Pixel

// Building the grid from reflection: addItem creates a single row window; addValue dispatches a
// field to the right editor (the editor registry first, then the built-in kinds); addStructInternal
// walks a struct's fields (handling categories and the notify interface). The refresh side of each
// editor lives with the editor (values/*.swg) and is driven by Properties.refreshItem.
internal impl Properties
{
    // Display name of a field: its Properties.Name attribute, or its beautified raw name.
    // Public so custom editors can label their widgets the same way the built-ins do.
    public func itemDisplayName(value: Swag.TypeValue)->String
    {
        let attrName = Reflection.getAttributeValue(value, Properties.Name, "name")
        if attrName != null do
            return cast(string) attrName
        return Utf8.beautifyName(value.name)
    }

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

            if .isGridLike()
            {
                .margin.z = .rightMargin
                .margin.y = .gridLineMargin * 0.5
                .margin.w = .gridLineMargin * 0.5
            }
            else do
                .setListContentPadding(line)
        }

        // Panel rows keep the same vertical breathing room between rows as the grid ones
        if .kind == .Panel
        {
            line.margin.y = .gridLineMargin * 0.5
            line.margin.w = .gridLineMargin * 0.5
        }

        with let item = .items.addNewPtr()
        {
            .line      = line
            .type      = value.pointedType
            .typeValue = value
            .data      = data
            .parent    = parentItem
            .level     = parentItem ? parentItem.level + 1 : 0
            .section   = parentItem ? parentItem.section : 0
            .valueCellHeight = height orelse .gridLineHeight
            // The focus/hot rectangle extends into the inter-row gap: half the line
            // margin, so two adjacent rows never overlap (Panel rows use the same
            // margin as the grid ones, see below).
            if .isGridLike() or .kind == .Panel do
                .extendFocus = .gridLineMargin * 0.5
        }

        line.hookOnEvent = func|prop = me, item|(wnd, evt) { return prop.onItemEvent(item, wnd, evt); }

        // Name
        if flags.has(.Name)
        {
            let dispName = itemDisplayName(value)

            // Panel rows label themselves: the composite editors carry the display name,
            // the row only keeps it for the string filter.
            if .kind == .Panel
            {
                if !dispName.isEmpty()
                {
                    if parentItem
                    {
                        item.filter += " "
                        item.filter = parentItem.filter
                        item.filter += " "
                    }
                    item.filter += dispName
                }
            }
            elif !dispName.isEmpty()
            {
                var labelWidth = cast(f32) .gridColumnSize
                if !.isGridLike() do
                    labelWidth = .listContentWidth()
                with let label = Label.create(line, dispName, {0, 0, labelWidth, item.line.position.height})
                {
                    if .isGridLike()
                    {
                        .vertAlignmentText = .Center
                        .horzAlignmentText = .Left
                        .dockStyle         = .Left
                        .margin.z          = .gridMarginColumn
                        .paddingText.x     = .leftMargin
                    }
                    else
                    {
                        .labelFlags |= .WordWrap | .AutoHeight | .DontAdaptSingleLineHeight
                        .vertAlignmentText = .Top
                        .horzAlignmentText = .Left
                        .margin.y          = .listNameMarginBefore
                        .margin.w          = .listNameMarginAfter
                    }

                    .style.setFont(.fontName)
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
                if !.isGridLike() and .kind != .Panel
                {
                    with let labelDesc = Label.create(line, "", {0, 0, .listContentWidth(), 0})
                    {
                        .labelFlags |= .WordWrap | .AutoHeight | .DontAdaptSingleLineHeight
                        .vertAlignmentText = .Top
                        .horzAlignmentText = .Left
                        .margin.w          = .listDescMarginAfter
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

            // A field embedded with 'using' is a flattened namespace in the language; mirror
            // that here and expand its fields inline, without a group row. The parent keeps its
            // own notify interface (the outer struct owns the row tree).
            if value.flags.has(.HasUsing)
            {
                .addStructInternal(typeSubStruct, data, parentItem, bindNotify: false)
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

    mtd addStructInternal(typeStruct: const *Swag.TypeInfoStruct, addr: [*] u8, parentItem: *PropertiesItem, bindNotify = true)
    {
        var newParent = parentItem

        // If the struct has implemented the notify interface, store it
        if parentItem and bindNotify do
            parentItem.ntfyItf = @mkinterface(addr, typeStruct, IPropertyNotify)

        // Currently open category path (nested subgroups). Each entry pairs a "/"-split name segment
        // with the header row created for it, so consecutive fields sharing a common prefix reuse the
        // same headers instead of recreating them.
        var categPath: Array'{ name: string, item: *PropertiesItem }

        // Walk order: declaration order, except when 'usingFieldsLast' pushes the 'using' base
        // structs after the struct's own fields — a derived type then edits its most specific
        // fields first even though the language forces the base to be declared first.
        var walkOrder: Array'u64
        for i in @countof(typeStruct.fields)
        {
            if !.usingFieldsLast or !typeStruct.fields[i].flags.has(.HasUsing) do
                walkOrder.add(i)
        }

        if .usingFieldsLast
        {
            for i in @countof(typeStruct.fields)
            {
                if typeStruct.fields[i].flags.has(.HasUsing) do
                    walkOrder.add(i)
            }
        }

        for idx in walkOrder
        {
            let value = typeStruct.fields[idx]
            // Opt-in mode (see addStructMulti 'onlyNamed'): a field participates only when it
            // carries an explicit display name. 'using' struct fields always recurse — their own
            // fields decide for themselves.
            if .buildOnlyNamed and
               !value.flags.has(.HasUsing) and
               !Reflection.hasAttribute(value, Properties.Name)
            {
                continue
            }

            // Category / nested subgroups
            let subCateg = Reflection.getAttributeValue(value, Properties.Category, "name")
            if subCateg != null
            {
                let segs = Tokenize.split(cast(string) subCateg, "/")

                // Keep the headers shared with the previously open path (longest common prefix),
                // drop the diverging tail, then create only the new segments.
                var common = 0'u64
                while common < categPath.count and common < segs.count and categPath[common].name == segs[common] do
                    common += 1

                categPath.count = common
                for i in common until segs.count
                {
                    let parentForCateg = categPath.count > 0 ? categPath[categPath.count - 1].item : parentItem
                    let citem          = .addCategoryHeader(segs[i], parentForCateg)
                    categPath.add({segs[i], citem})
                }

                newParent = categPath.count > 0 ? categPath[categPath.count - 1].item : parentItem
            }

            // Decorators (Space / Header / HelpBox) go above the field, under the same parent so
            // they collapse with their category. Count them together with the field's own rows so
            // every open category shows a disclosure and hides its whole block when collapsed.
            let numItemsBefore = .items.count
            .addDecorators(value, newParent)
            .addValue(value, addr + value.offset, newParent)

            let added = cast(u32) (.items.count - numItemsBefore)
            for &c in categPath do
                c.item.numChilds += added
        }
    }

    // A thin horizontal separator row, the same look as a Panel category divider. Public so a
    // host appending hand-made rows (addItem) after the generated content can separate them;
    // call endAppendRows once done. 'name' feeds the notify visibility dispatch and the filter.
    public mtd addSeparator(name: string = null, parentItem: #null *PropertiesItem = null)->*PropertiesItem
    {
        let v: Swag.TypeValue{name: name}
        with let item = .addItem(v, null, parentItem, 1, .Zero)
        {
            .flags.add(.NoSeparator | .NoFocus)
            .line.margin.y        = 15
            .line.margin.w        = 8
            .line.backgroundStyle = .Dialog
        }

        return item
    }

    // To be called once after appending custom rows (addItem / addSeparator) from outside the
    // reflection build, so visibility states, layout and the scroll size account for them.
    public mtd endAppendRows()
    {
        .updateStates()
    }

    // Create one category/subgroup header row under 'parentForCateg'. A top-level category (whose
    // parent is the section, not another category) stays at level 0 like a full-width divider; a
    // category nested under another keeps addItem's level (parent + 1) so it and its fields indent
    // one step further.
    mtd addCategoryHeader(name: string, parentForCateg: *PropertiesItem)->*PropertiesItem
    {
        // Panel: a category paints as a thin separator line, not a titled header
        if .kind == .Panel
        {
            let item = .addSeparator(name, parentForCateg)
            item.flags.add(.Category | .Expanded)
            .sections.add({item, 1})
            return item
        }

        let v: Swag.TypeValue{name: name}
        let item = .addItem(v, null, parentForCateg)
        item.label.style.setFont(&.fontCategory)
        item.flags.add(.Category | .NoSeparator | .Expanded | .NoFocus)
        if !parentForCateg.flags.has(.Category) do
            item.level = 0
        .sections.add({item, 1})
        return item
    }

    // Inject the decorator rows declared on 'value' (Space, Header, HelpBox) above the field, in a
    // fixed visual order. Grid modes only — list mode already stacks its own per-row description.
    mtd addDecorators(value: Swag.TypeValue, parentItem: *PropertiesItem)
    {
        if !.isGridLike() do
            return

        if let space = Reflection.getAttributeValue(value, .Gap, "size") do
            .addSpacerRow(parentItem, cast(s32) assume space)
        if let header = Reflection.getAttributeValue(value, .Heading, "text") do
            .addHeaderRow(cast(string) header, parentItem)
        if let help = Reflection.getAttributeValue(value, .HelpBox, "text") do
            .addNoteRow(cast(string) help, parentItem)
    }

    // A blank vertical gap ('size' px). It paints nothing (paintBackItem short-circuits on .Spacer).
    mtd addSpacerRow(parentItem: *PropertiesItem, size: s32)->*PropertiesItem
    {
        with let item = .addItem(Swag.TypeValue{}, null, parentItem, cast(f32) size, .Zero)
        {
            .level = parentItem.level
            .flags.add(.Spacer | .NoSeparator | .NoFocus)
        }

        return item
    }

    // A non-collapsible bold divider label spanning the row (Unity [Header]-style), aligned with the
    // sibling fields it introduces.
    mtd addHeaderRow(text: string, parentItem: *PropertiesItem)->*PropertiesItem
    {
        let v: Swag.TypeValue{name: text}
        with let item = .addItem(v, null, parentItem)
        {
            if .label do
                .label.style.setFont(&.fontCategory)
            .level = parentItem.level
            .flags.add(.Header | .NoSeparator | .NoFocus)
        }
        return item
    }

    // An informational note spanning the row, styled like the info validation bar (icon + text on a
    // soft info background). The bar is painted by paintBackItem on the .Note flag; the label drawn
    // on top carries the icon and text.
    mtd addNoteRow(text: string, parentItem: *PropertiesItem)->*PropertiesItem
    {
        let item = .addItem(Swag.TypeValue{}, null, parentItem, 0, .Zero)
        item.level = parentItem.level
        item.flags.add(.Note | .NoSeparator | .NoFocus)

        with let lbl = Label.create(item.line, text, {0, 0, .position.width, item.line.position.height})
        {
            .focusStrategy     = .None
            .horzAlignmentText = .Left
            .vertAlignmentText = .Center
            .horzAlignmentIcon = .Left
            .paddingIcon.x     = (.valBarGlyphWidth - .valBarIconSize) * 0.5
            .paddingText       = {.valBarGlyphWidth, 0, .valBarPaddingX, 0}
            .dockStyle         = .Center
        }
        item.label = lbl

        // Icon + colors come from the theme and are re-applied on a theme switch (applyNoteVisual),
        // exactly like the validation bar — a plain Label color field does not follow the theme, so
        // baking it here would keep the build-time theme's color (wrong on the first paint / after a
        // theme change).
        .applyNoteVisual(item)
        return item
    }
}
