#global public

using Core, Pixel

// Building the grid from reflection: addItem creates a single row window; addValue dispatches a
// field to the right editor (the editor registry first, then the built-in kinds); addStructInternal
// walks a struct's fields (handling categories and the notify interface). The refresh side of each
// editor lives with the editor (values/*.swg) and is driven by Properties.refreshItem.
internal impl Properties
{
    func attributeString(value: #null any)->string
    {
        return cast(string) value!
    }

    // The string an attribute declares, as the reader sees it: an attribute value is a
    // compile-time constant, so the installed resolver is what can turn it into a
    // translation. See Properties.setTextResolver.
    func attributeText(value: #null any)->string
    {
        return resolveText(attributeString(value))
    }

    // Display name of a field: its Properties.Name attribute, or its beautified raw name.
    //
    // Both are declared in source, so both go through the text resolver and a field labels
    // itself the same way whether or not it carries an explicit name. A synthetic value
    // carries no type — a section header names itself with a string its caller already
    // chose, and translating that string a second time is not this grid's business.
    // Public so custom editors can label their widgets the same way the built-ins do.
    public func itemDisplayName(value: Swag.TypeValue)->String
    {
        let attrName = Reflection.attributeValue(value, Properties.Name, "name")
        if attrName != null do
            return attributeText(attrName)

        let beautified = Utf8.beautifyName(value.name orelse "")
        if value.pointedType == null do
            return beautified
        return resolveText(beautified.toString())
    }

    // Create a row for 'value' (field typeinfo + name) bound to 'data' under 'parentItem'.
    // Public so custom editors registered with registerEditor (possibly authored in another
    // module) can build their row the same way the built-in editors do.
    public mtd addItem(value: Swag.TypeValue, data: #null *u8, parentItem: #null *PropertiesItem, height: f32 = 0, flags = PropertiesAddItemFlags.Name | PropertiesAddItemFlags.Description)->*PropertiesItem
    {
        var line: #null *Wnd

        if .isGridLike() do
            line = Wnd.create'Wnd(.edView, {0, 0, .position.width, height != 0 ? height : .gridLineHeight})
        else
        {
            let stk = StackLayoutCtrl.create(.edView, .Top, {0, 0, .position.width, height != 0 ? height : .gridLineHeight})
            stk.fitToContent = true
            line             = stk
        }

        with line
        {
            .wndFlags.add(.BeforeChildrenPaint)

            // Lines never take the keyboard focus themselves: navigation lives on
            // the edView and edition on the row editors. This keeps a click on a
            // row label from stealing focus away from the navigation surface.
            .focusPolicy = .None

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

        with let item = .items.addNew()
        {
            .initialize(line!, value.pointedType, value, data, parentItem)
            .level           = parentItem ? parentItem.level + 1 : 0
            .section         = parentItem ? parentItem.section : 0
            .valueCellHeight = height != 0 ? height : .gridLineHeight

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
                        .setTextAlignment(.Left, .Center)
                        .setTextPadding({.leftMargin, 0, 0, 0})
                        .dockStyle = .Left
                        .margin.z  = .gridMarginColumn
                    }
                    else
                    {
                        .updateFlags(.WordWrap | .AutoHeight)
                        .setTextAlignment(.Left, .Top)
                        .margin.y = .listNameMarginBefore
                        .margin.w = .listNameMarginAfter
                    }

                    .style.setFont(.fontName)
                }

                item.assignLabel(label)
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
        let dispDesc = Reflection.attributeValue(value, Properties.Description, "desc")
        if dispDesc != null
        {
            let descText = attributeText(dispDesc)
            item.filter += " "
            item.filter += descText
            item.assignDescription(descText)

            if flags.has(.Description)
            {
                if !.isGridLike() and .kind != .Panel
                {
                    with let labelDesc = Label.create(line, "", {0, 0, .listContentWidth(), 0})
                    {
                        .updateFlags(.WordWrap | .AutoHeight)
                        .setTextAlignment(.Left, .Top)
                        .margin.w = .listDescMarginAfter
                        .setText(descText)
                        item.assignDescriptionLabel(labelDesc)
                    }
                }
            }
        }

        return item
    }

    mtd addValue(value: Swag.TypeValue, data: #null [*] u8, parentItem: #null *PropertiesItem)
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
            let typeArr        = cast(const *Swag.TypeInfoArray) value.pointedType!
            let numItemsBefore = .items.count

            var newData = data
            for [i] in typeArr.count
            {
                var subValue: Swag.TypeValue
                subValue.name        = Format.toString("%", i).toString()
                subValue.pointedType = typeArr.pointedType
                .addValue(subValue, newData, item)
                newData += typeArr.pointedType.sizeof
            }

            item.numChilds += cast(u32) (.items.count - numItemsBefore)

        case Reflection.isEnum(value.pointedType):
            let typeEnum = cast(const *Swag.TypeInfoEnum) value.pointedType!
            .constructEnum(value, typeEnum, data, parentItem)

        case value.pointedType == Core.String:
            .constructDynamicString(value, data, parentItem)

        case Reflection.isString(value.pointedType):
            .constructStaticString(value, data, parentItem)

        case Reflection.isBool(value.pointedType):
            .constructBool(value, data, parentItem)

        case Reflection.isInteger(value.pointedType) or Reflection.isFloat(value.pointedType):
            let typeNative = cast(const *Swag.TypeInfoNative) value.pointedType!
            .constructNative(value, typeNative, data, parentItem)

        case value.pointedType == Array:
            .constructArray(value, data, parentItem)

        case Reflection.isStruct(value.pointedType):
            let typeSubStruct = cast(const *Swag.TypeInfoStruct) value.pointedType!
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
            let pItem = parentItem!
            pItem.flags.add(.NoSeparator | .NoFocus)
            let item           = .addItem(value, data, parentItem)
            let numItemsBefore = .items.count
            .addStructInternal(typeSubStruct, data, item)
            item.numChilds = cast(u32) (.items.count - numItemsBefore)
        }
    }

    mtd addStructInternal(typeStruct: const *Swag.TypeInfoStruct, addr: #null [*] u8, parentItem: #null *PropertiesItem, bindNotify = true)
    {
        var newParent = parentItem

        // If the struct has implemented the notify interface, store it
        if parentItem and bindNotify do
            parentItem.ntfyItf = @mkinterface(addr, typeStruct, IPropertyNotify)

        // Currently open category path (nested subgroups). Each entry pairs a "/"-split name segment
        // with the header row created for it, so consecutive fields sharing a common prefix reuse the
        // same headers instead of recreating them.
        var categPath: Array'{ name: #null string, item: #null *PropertiesItem }

        // Walk order: declaration order, except when 'usingFieldsLast' pushes the 'using' base
        // structs after the struct's own fields — a derived type then edits its most specific
        // fields first even though the language forces the base to be declared first.
        var walkOrder: Array'u64
        let tsFields = typeStruct.fields!
        for [i] in @countof(typeStruct.fields)
        {
            if !.usingFieldsLast or !tsFields[i].flags.has(.HasUsing) do
                walkOrder.add(i)
        }

        if .usingFieldsLast
        {
            for [i] in @countof(typeStruct.fields)
            {
                if tsFields[i].flags.has(.HasUsing) do
                    walkOrder.add(i)
            }
        }

        for idx in walkOrder
        {
            let value = tsFields[idx]

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
            let subCateg = Reflection.attributeValue(value, Properties.Category, "name")
            if subCateg != null
            {
                let segs = Tokenize.split(attributeString(subCateg), "/")

                // Keep the headers shared with the previously open path (longest common prefix),
                // drop the diverging tail, then create only the new segments.
                var common = 0'u64
                while common < categPath.count and common < segs.count and categPath[common].name == segs[common] do
                    common += 1

                categPath.count = common

                // Consecutive fields sharing the same category leave no new segment to
                // create (common == segs.count); an empty 'until' range is a safety
                // error, so guard the loop.
                if common < segs.count
                {
                    for [i] in common until segs.count
                    {
                        let parentForCateg = categPath.count > 0 ? categPath[categPath.count - 1].item : parentItem
                        let citem          = .addCategoryHeader(segs[i], parentForCateg)
                        categPath.add({segs[i], citem})
                    }
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
            for &c in categPath
            {
                let categItem = c.item!
                categItem.numChilds += added
            }
        }
    }

    // A thin horizontal separator row, the same look as a Panel category divider. Public so a
    // host appending hand-made rows (addItem) after the generated content can separate them;
    // call endAppendRows once done. 'name' feeds the notify visibility dispatch and the filter.
    public mtd addSeparator(name: #null string = null, parentItem: #null *PropertiesItem = null)->*PropertiesItem
    {
        let v = Swag.TypeValue{name: name}
        with let item = .addItem(v, null, parentItem, 1, .None)
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

    // Create one category/subgroup header row under 'parentForCateg', named by the segment its
    // Category attribute declares. A top-level category (whose parent is the section, not another
    // category) stays at level 0 like a full-width divider; a category nested under another keeps
    // addItem's level (parent + 1) so it and its fields indent one step further.
    //
    // The row keeps the declared segment as its identity — a host looks a category up by the name
    // it wrote, and the nested-path matching in addStructInternal compares against it — so only
    // the header shown to the reader goes through the text resolver.
    mtd addCategoryHeader(name: #null string, parentForCateg: #null *PropertiesItem)->*PropertiesItem
    {
        // Panel: a category paints as a thin separator line, not a titled header
        if .kind == .Panel
        {
            let item = .addSeparator(name, parentForCateg)
            item.flags.add(.Category | .Expanded)
            .sections.add({item, 1})
            return item
        }

        let v    = Swag.TypeValue{name: name}
        let item = .addItem(v, null, parentForCateg)
        item.label.setText(resolveText(name orelse ""))
        item.label.style.setFont(&.fontCategory)
        item.flags.add(.Category | .NoSeparator | .Expanded | .NoFocus)
        if !parentForCateg!.flags.has(.Category) do
            item.level = 0
        .sections.add({item, 1})
        return item
    }

    // Inject the decorator rows declared on 'value' (Space, Header, HelpBox) above the field, in a
    // fixed visual order. Grid modes only — list mode already stacks its own per-row description.
    mtd addDecorators(value: Swag.TypeValue, parentItem: #null *PropertiesItem)
    {
        if !.isGridLike() do
            return

        if let space = Reflection.attributeValue(value, .Gap, "size") do
            .addSpacerRow(parentItem, cast(s32) space)
        if let header = Reflection.attributeValue(value, .Heading, "text") do
            .addHeaderRow(attributeText(header), parentItem)
        if let help = Reflection.attributeValue(value, .HelpBox, "text") do
            .addNoteRow(attributeText(help), parentItem)
    }

    // A blank vertical gap ('size' px). It paints nothing (paintBackItem short-circuits on .Spacer).
    mtd addSpacerRow(parentItem: #null *PropertiesItem, size: s32)->*PropertiesItem
    {
        with let item = .addItem(Swag.TypeValue{}, null, parentItem, cast(f32) size, .None)
        {
            .level = parentItem!.level
            .flags.add(.Spacer | .NoSeparator | .NoFocus)
        }

        return item
    }

    // A non-collapsible bold divider label spanning the row (Unity [Header]-style), aligned with the
    // sibling fields it introduces.
    mtd addHeaderRow(text: #null string, parentItem: #null *PropertiesItem)->*PropertiesItem
    {
        let v = Swag.TypeValue{name: text}
        with let item = .addItem(v, null, parentItem)
        {
            if @isset(.label) do
                .label.style.setFont(&.fontCategory)
            .level = parentItem!.level
            .flags.add(.Header | .NoSeparator | .NoFocus)
        }

        return item
    }

    // An informational note spanning the row, styled like the info validation bar (icon + text on a
    // soft info background). The bar is painted by paintBackItem on the .Note flag; the label drawn
    // on top carries the icon and text.
    mtd addNoteRow(text: #null string, parentItem: #null *PropertiesItem)->*PropertiesItem
    {
        let item = .addItem(Swag.TypeValue{}, null, parentItem, 0, .None)
        item.level = parentItem!.level
        item.flags.add(.Note | .NoSeparator | .NoFocus)

        with let lbl = Label.create(item.line, text, {0, 0, .position.width, item.line.position.height})
        {
            .setTextAlignment(.Left, .Center)
            .setIconHorizontalAlignment(.Left)
            .setIconPadding({(.valBarGlyphWidth - .valBarIconSize) * 0.5, 0, 0, 0})
            .setTextPadding({.valBarGlyphWidth, 0, .valBarPaddingX, 0})
            .dockStyle = .Center
        }

        item.assignLabel(lbl)

        // Icon + colors come from the theme and are re-applied on a theme switch (applyNoteVisual),
        // exactly like the validation bar — a plain Label color field does not follow the theme, so
        // baking it here would keep the build-time theme's color (wrong on the first paint / after a
        // theme change).
        .applyNoteVisual(item)
        return item
    }
}
