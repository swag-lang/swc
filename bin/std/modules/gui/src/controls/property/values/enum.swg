internal impl Properties
{
    // Dynamic per-value filter of an enum field (IPropertyNotify.isEnumValueVisible):
    // consulted on the host notify and along the item's parent chain, at build time.
    mtd isEnumValueShown(item: *PropertiesItem, enumValue: Swag.TypeValue)->bool
    {
        if .hostNtfy and !.hostNtfy.isEnumValueVisible(me, item, enumValue) do
            return false

        var scan = cast(#null *PropertiesItem) item
        while scan
        {
            if scan.ntfyItf and !scan.ntfyItf.isEnumValueVisible(me, item, enumValue) do
                return false
            scan = scan.parent
        }

        return true
    }

    mtd refreshEnumFlags(item: *PropertiesItem)
    {
        if @isset(item.checkBox)
        {
            var val1, val2: u64
            switch item.typeValue.pointedType!.sizeof
            {
            case 1:
                val1 = cast(u64) item.data![as u8]
                val2 = cast(u64) item.typeValue.value![as u8]

            case 2:
                val1 = cast(u64) item.data![as u16]
                val2 = cast(u64) item.typeValue.value![as u16]

            case 4:
                val1 = cast(u64) item.data![as u32]
                val2 = cast(u64) item.typeValue.value![as u32]

            case 8:
                val1 = cast(u64) item.data![as u64]
                val2 = cast(u64) item.typeValue.value![as u64]
            }

            // Multi-selection: a flag whose bit disagrees across instances is indeterminate.
            if .flagBitIsMixed(item, val2) do
                item.checkBox.setState(.Indeterminate)
            else do
                item.checkBox.setState(val1 & val2 ? .Checked : .Unchecked)
            item.checkBox.invalidate()
        }
    }

    mtd refreshEnum(item: *PropertiesItem)
    {
        if @isset(item.comboBox)
        {
            let typeEnum = cast(const *Swag.TypeInfoEnum) item.typeValue.pointedType!

            var val1, val2:   u64
            var val1s, val2s: #null string
            switch typeEnum.rawType!.sizeof
            {
            case 1:  val1 = cast(u64) item.data![as u8]
            case 2:  val1 = cast(u64) item.data![as u16]
            case 4:  val1 = cast(u64) item.data![as u32]
            case 8:  val1 = cast(u64) item.data![as u64]
            case 16: val1s = item.data![as string]
            }

            var idxSel = 0'u64
            for v, idx in typeEnum.values
            {
                switch typeEnum.rawType!.sizeof
                {
                case 1:  val2 = cast(u64) v.value![as u8]
                case 2:  val2 = cast(u64) v.value![as u16]
                case 4:  val2 = cast(u64) v.value![as u32]
                case 8:  val2 = cast(u64) v.value![as u64]
                case 16: val2s = v.value![as string]
                }

                if val1 == val2 and val1s == val2s do
                    idxSel = idx
            }

            // The combo may hide values (isEnumValueVisible): each combo entry carries its
            // enum value index in userData0, so map the selected enum index to its combo
            // slot. A hidden current value simply shows no selection.
            var idxCombo = Swag.U32.Max
            for cb, cbIdx in item.comboBox.items
            {
                if cast(u64) cb!.userData0 == idxSel
                {
                    idxCombo = cast(u32) cbIdx
                    break
                }
            }

            // Multi-selection: clear the selection when the instances disagree.
            if .fieldIsMixed(item) or idxCombo == Swag.U32.Max do
                item.comboBox.clearSelection(notify: false)
            else do
                item.comboBox.setSelectedIndex(idxCombo, notify: false)
        }
    }

    mtd validateEnumFlags(item: *PropertiesItem)
    {
        if @isset(item.checkBox)
        {
            // Set/clear this one flag bit in every edited instance (other bits, which may
            // differ per instance, are left alone). The row's mask is the flag value.
            let sz   = item.typeValue.pointedType!.sizeof
            let mask = readEnumBits(cast(#null *u8) item.checkBox.userData, sz)
            .writeEnumBit(item, mask, item.checkBox.isChecked())
        }

        .commitItemChange(item)
    }

    mtd validateEnum(item: *PropertiesItem)
    {
        if @isset(item.comboBox)
        {
            #[Swag.Mixin]
            func(T) setEd()
            {
                let p  = cast(*T) item.data!
                let p1 = cast(const *T) typeEnum.values![idxEnum].value!
                p[] = p1[]
            }

            let typeEnum = cast(const *Swag.TypeInfoEnum) item.typeValue.pointedType!
            let sel      = item.comboBox.selectedIndex

            // A deselected combo means "mixed" was just shown (multi-selection); there is
            // no concrete value to write, so don't touch the instances.
            if sel >= item.comboBox.items.count do
                return

            // Combo slot -> enum value index (the combo may hide values, see constructEnum)
            let idxEnum = cast(u64) item.comboBox.items[sel]!.userData0

            switch typeEnum.rawType!.sizeof
            {
            case 1:  setEd'u8()
            case 2:  setEd'u16()
            case 4:  setEd'u32()
            case 8:  setEd'u64()
            case 16: setEd'string()
            }
        }

        .commitItemChange(item)
    }

    mtd constructEnumFlags(value: Swag.TypeValue, typeEnum: const *Swag.TypeInfoEnum, data: #null *u8, parentItem: #null *PropertiesItem)
    {
        let item = .addItem(value, data, parentItem)
        item.flags.add(.NoSeparator | .Expanded)
        var numChilds: u32

        for v in typeEnum.values
        {
            // The host can hide values (isEnumValueVisible): skip their row entirely
            if !.isEnumValueShown(item, v) do
                continue

            with let line = Wnd.create'Wnd(me.edView)
            {
                .wndFlags.set(.BeforeChildrenPaint)
                .focusPolicy = .None     // navigation lives on edView, edition on the checkbox
                if me.isGridLike() do
                    .margin.z = me.rightMargin
                else
                {
                    .maxSize.x = me.listUsefulWidth()
                    me.setListContentPadding(line)
                }

                .margin.y = me.listNameMarginAfter
                .margin.w = me.listNameMarginAfter
            }

            with let itemB = me.items.addNew()
            {
                .initialize(line, typeEnum, v, data, item)
                .filter        = item.filter
                .level         = item.level + 1
                .section       = item.section
                .selfPropagate = true     // toggles a single bit across all instances
                .flags.add(.NoSeparator)
            }

            line.hookOnEvent = func|prop = me, itemB|(hwnd, evt) { return prop.onItemEvent(itemB, hwnd, evt); }

            let checkHeight = me.kind == .Condensed ? PropCondensedControlHeight : me.gridLineHeight
            with let ed     = CheckButton.create(line, "", {0, 0, checkHeight, checkHeight})
            {
                if me.isGridLike() do
                    .margin.x = me.leftMargin
                .dockStyle = .Left
                .userData  = cast #unconst (#null *void) v.value
            }

            itemB.assignCheckBox(ed)

            let dispDesc    = Reflection.attributeValue(v, Properties.Description, "desc")
            let dispDescStr = dispDesc == null ? "" : attributeText(dispDesc)
            itemB.filter += dispDescStr

            var labelWidth = me.position.width - item.line.position.height
            if !me.isGridLike() do
                labelWidth = me.listContentWidth() - me.gridLineHeight
            with let label1 = Label.create(line, "", {item.line.position.height, 0, Math.max(labelWidth, 1.0)})
            {
                .dockStyle = .Center
                if me.kind == .Condensed do
                    .margin.x = PropCondensedCheckTextGap
                .updateFlags(.WordWrap | .AutoHeight)
                .setTextHorizontalAlignment(.Left)
                .setText(dispDescStr)
            }

            let minHeight = me.kind == .Condensed ? me.gridLineHeight : ed.position.height
            itemB.sigResize += func|label1, line, minHeight|(itemB)
            {
                label1.updateAutomaticHeight()
                line.position.height = Math.max(minHeight, label1.position.height)
                line.applyLayout()
            }

            .refreshEnumFlags(itemB)
            itemB.checkBox.sigChanged += func|prop = me, itemB|(ed) { prop.validateEnumFlags(itemB) }

            numChilds += 1
        }

        item.numChilds = numChilds
    }

    mtd constructEnum(value: Swag.TypeValue, typeEnum: const *Swag.TypeInfoEnum, data: #null *u8, parentItem: #null *PropertiesItem)
    {
        if Reflection.hasAttribute(value.pointedType, Swag.EnumFlags)
        {
            .constructEnumFlags(value, typeEnum, data, parentItem)
            return
        }

        let item = .addItem(value, data, parentItem)

        // Panel row: a full-width labeled combo, right edge aligned with the other editors
        if .kind == .Panel
        {
            if @isset(item.label) do
                item.label.hide()
            with let ctrl = ComboCtrl.create(item.line, itemDisplayName(value).toString())
            {
                .anchorStyle = .Right
                .setLayoutMetrics(.labelWidth, cast(f32) Reflection.attributeValue(value, me.EditSize, "size", 0))
            }

            item.assignComboBox(ctrl.combo)
        }
        else
        {
            var editWidth = cast(f32) Reflection.attributeValue(value, me.EditSize, "size", me.editorWidth)
            if !me.isGridLike() do
                editWidth = me.listContentWidthFromUseful(editWidth)
            with let ed = ComboBox.create(item.line)
            {
                .maxSize.x = editWidth
                if me.isGridLike() do
                    .dockStyle = .CenterKeepSizeVert
                else do
                    .preferredSize.x = editWidth
                if me.kind == .Condensed do
                    .updateFlags(.Flat)
            }

            me.adaptCondensedControl(ed)
            item.assignComboBox(ed)
        }

        // An enum value can carry its own display name ('1...2...3...' for Number). The
        // host can hide values (isEnumValueVisible); each combo entry keeps its enum
        // value index in userData0 so refresh/validate stay index-agnostic.
        for v, idx in typeEnum.values
        {
            if !.isEnumValueShown(item, v) do
                continue
            let dn = Reflection.attributeValue(v, Properties.Name, "name")
            item.comboBox.addItem(dn == null ? resolveText(v.name orelse "") : attributeText(dn), userData0: cast(#null *void) idx)
        }

        .refreshEnum(item)
        item.comboBox.sigChanged += func|prop = me, item|(ed, n) { prop.validateEnum(item) }
    }
}
