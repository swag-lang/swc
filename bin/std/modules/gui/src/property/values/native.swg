impl Properties
{
    mtd refreshNative(item: *PropertiesItem)
    {
        let typeNative = cast(#null const *Swag.TypeInfoNative) item.typeValue.pointedType
        let data       = item.data

        if #isset(item.sliderBox)
        {
            #[Swag.Mixin]
            func(T) setEd()
            {
                let p = cast(#null *T) data
                item.sliderBox.slider.setValue(cast(f32) dref p)
            }

            item.sliderBox.invalidate()
            switch typeNative.nativeKind
            {
            case U8:
                setEd'u8()
            case U16:
                setEd'u16()
            case U32:
                setEd'u32()
            case U64:
                setEd'u64()
            case S8:
                setEd's8()
            case S16:
                setEd's16()
            case S32:
                setEd's32()
            case S64:
                setEd's64()
            case F32:
                setEd'f32()
            case F64:
                setEd'f64()
            }

            .setEditMixed(item, item.sliderBox.edit)
        }
        elif #isset(item.editBox)
        {
            #[Swag.Mixin]
            func(T) setEd()
            {
                let p = cast(#null *T) data
                item.editBox.setText(Format.toString("%", dref p))
            }

            item.editBox.invalidate()
            switch typeNative.nativeKind
            {
            case U8:
                setEd'u8()
            case U16:
                setEd'u16()
            case U32:
                setEd'u32()
            case U64:
                setEd'u64()
            case S8:
                setEd's8()
            case S16:
                setEd's16()
            case S32:
                setEd's32()
            case S64:
                setEd's64()
            case F32:
                setEd'f32()
            case F64:
                setEd'f64()
            }

            .setEditMixed(item, item.editBox)
        }
    }

    mtd validateNative(item: *PropertiesItem)
    {
        let typeNative = cast(#null const *Swag.TypeInfoNative) item.typeValue.pointedType
        let data       = item.data

        if #isset(item.sliderBox)
        {
            #[Swag.Mixin]
            func(T) setEd()
            {
                var p = cast(#null *T) data
                dref p = cast(T) item.sliderBox.slider.getValue()
            }

            switch typeNative.nativeKind
            {
            case U8:
                setEd'u8()
            case U16:
                setEd'u16()
            case U32:
                setEd'u32()
            case U64:
                setEd'u64()
            case S8:
                setEd's8()
            case S16:
                setEd's16()
            case S32:
                setEd's32()
            case S64:
                setEd's64()
            case F32:
                setEd'f32()
            case F64:
                setEd'f64()
            }
        }
        elif #isset(item.editBox)
        {
            #[Swag.Mixin]
            func(T) setEd()
            {
                var p = cast(#null *T) data
                dref p = catch StrConv.toNum'T(txt)
            }

            let txt = item.editBox.getText()
            switch typeNative.nativeKind
            {
            case U8:
                setEd'u8()
            case U16:
                setEd'u16()
            case U32:
                setEd'u32()
            case U64:
                setEd'u64()
            case S8:
                setEd's8()
            case S16:
                setEd's16()
            case S32:
                setEd's32()
            case S64:
                setEd's64()
            case F32:
                setEd'f32()
            case F64:
                setEd'f64()
            }
        }

        .hasChanged(item)
    }

    // Panel row: a full-width self-labeled composite (labeled slider or labeled edit box)
    mtd constructNativePanel(item: *PropertiesItem, value: Swag.TypeValue, typeNative: const *Swag.TypeInfoNative)
    {
        var dispName = itemDisplayName(value)

        if Reflection.hasAttribute(value, .SliderMinMax)
        {
            with let slider = SliderCtrl.create(item.line, dispName.toString())
            {
                .anchorStyle  = .X
                .autoEditSize = false
                .labelSize    = 60
                // Enough for a 3-4 digit value plus a unit; a bigger box would eat the track.
                .editSize     = 64
            }

            item.sliderBox = slider

            let unit = Reflection.getAttributeValue(value, .Unit, "value")
            if unit != null do
                slider.edit.unit = cast(string) (unit)

            let minV = cast(f32) notnull Reflection.getAttributeValue(value, .SliderMinMax, "min")
            let maxV = cast(f32) notnull Reflection.getAttributeValue(value, .SliderMinMax, "max")

            // Whole bounds read as an integer slider (no trailing decimals), even for a
            // float field whose values are conceptually whole (a size, an angle...).
            let whole = minV == Math.floor(minV) and maxV == Math.floor(maxV)

            switch typeNative.nativeKind
            {
            case U8, U16, U32, U64:
                slider.setMinMaxU64(cast() minV, cast() maxV)
            case S8, S16, S32, S64:
                slider.setMinMaxS64(cast() minV, cast() maxV)
            case F32, F64:
                if whole do
                    slider.setMinMaxS64(cast() minV, cast() maxV)
                else do
                    slider.setMinMaxF32(minV, maxV)
            }

            return
        }

        with let ctrl = EditCtrl.create(item.line, dispName.toString(), "", flags: .AutoLoseFocus)
        {
            .anchorStyle = .X
            .editSize    = 0
        }

        let unit = Reflection.getAttributeValue(value, .Unit, "value")
        if unit != null do
            ctrl.edit.unit = cast(string) (unit)

        item.editBox = ctrl.edit

        var minV, maxV: s64
        var hasMinMax = false
        if Reflection.hasAttribute(value, .MinMax)
        {
            hasMinMax = true
            minV      = cast(s64) notnull Reflection.getAttributeValue(value, .MinMax, "min")
            maxV      = cast(s64) notnull Reflection.getAttributeValue(value, .MinMax, "max")
        }

        switch typeNative.nativeKind
        {
        case U8, U16, U32, U64:
            if !hasMinMax do
                ctrl.edit.setInputU64()
            else do
                ctrl.edit.setInputU64(cast() minV, cast() maxV)
        case S8, S16, S32, S64:
            if !hasMinMax do
                ctrl.edit.setInputS64()
            else do
                ctrl.edit.setInputS64(cast() minV, cast() maxV)
        case F32, F64:
            if !hasMinMax do
                ctrl.edit.setInputF64()
            else do
                ctrl.edit.setInputF64(cast() minV, cast() maxV)
        }
    }

    mtd constructNative(value: Swag.TypeValue, typeNative: const *Swag.TypeInfoNative, data: #null *u8, parentItem: #null *PropertiesItem)
    {
        let item = .addItem(value, data, parentItem)

        if .kind == .Panel
        {
            .constructNativePanel(item, value, typeNative)
        }
        elif Reflection.hasAttribute(value, .SliderMinMax)
        {
            var editWidth = cast(f32) Reflection.getAttributeValue(value, me.EditSize, "size", me.sizeEditValue)
            if !me.isGridLike() do
                editWidth = me.listContentWidthFromUseful(editWidth)
            with let slider = SliderCtrl.create(item.line, null)
            {
                .labelSize = 0
                .maxSize.x = editWidth
                if me.isGridLike() do
                    .dockStyle = .CenterKeepSizeVert
                else do
                    // Fixed edit width: an anchored width would drift with the resize
                    // history and break the right-edge alignment across editors
                    .preferredSize.x = editWidth
            }

            me.adaptCondensedControl(slider)
            me.flattenCondensedEdit(notnull slider.edit)
            item.sliderBox = slider

            let unit = Reflection.getAttributeValue(value, .Unit, "value")
            if unit != null do
                slider.edit.unit = cast(string) (unit)

            let minV = cast(f32) notnull Reflection.getAttributeValue(value, .SliderMinMax, "min")
            let maxV = cast(f32) notnull Reflection.getAttributeValue(value, .SliderMinMax, "max")

            switch typeNative.nativeKind
            {
            case U8, U16, U32, U64:
                slider.setMinMaxU64(cast() minV, cast() maxV)
            case S8, S16, S32, S64:
                slider.setMinMaxS64(cast() minV, cast() maxV)
            case F32, F64:
                slider.setMinMaxF32(minV, maxV)
            }
        }
        else
        {
            let unit = Reflection.getAttributeValue(value, .Unit, "value")
            var editWidth = cast(f32) Reflection.getAttributeValue(value, me.EditSize, "size", me.sizeEditValue)
            if !me.isGridLike() do
                editWidth = me.listContentWidthFromUseful(editWidth)

            with let ed = EditBox.create(item.line, value.name)
            {
                if unit != null do
                    .unit = cast(string) (unit)
                .maxSize.x = editWidth
                if me.isGridLike() do
                    .dockStyle = .CenterKeepSizeVert
                else do
                    .preferredSize.x = editWidth
            }

            me.adaptCondensedControl(ed)
            me.flattenCondensedEdit(ed)

            var minV, maxV: s64
            var hasMinMax = false
            if Reflection.hasAttribute(value, .MinMax)
            {
                hasMinMax = true
                minV      = cast(s64) notnull Reflection.getAttributeValue(value, .MinMax, "min")
                maxV      = cast(s64) notnull Reflection.getAttributeValue(value, .MinMax, "max")
            }

            item.editBox = ed
            switch typeNative.nativeKind
            {
            case U8:
                if !hasMinMax do
                    ed.setInputU64(Swag.U8.Min, Swag.U8.Max)
                else do
                    ed.setInputU64(cast() minV, cast() maxV)
            case U16:
                if !hasMinMax do
                    ed.setInputU64(Swag.U16.Min, Swag.U16.Max)
                else do
                    ed.setInputU64(cast() minV, cast() maxV)
            case U32:
                if !hasMinMax do
                    ed.setInputU64(Swag.U32.Min, Swag.U32.Max)
                else do
                    ed.setInputU64(cast() minV, cast() maxV)
            case U64:
                if !hasMinMax do
                    ed.setInputU64(Swag.U64.Min, Swag.U64.Max)
                else do
                    ed.setInputU64(cast() minV, cast() maxV)

            case S8:
                if !hasMinMax do
                    ed.setInputS64(Swag.S8.Min, Swag.S8.Max)
                else do
                    ed.setInputS64(cast() minV, cast() maxV)
            case S16:
                if !hasMinMax do
                    ed.setInputS64(Swag.S16.Min, Swag.S16.Max)
                else do
                    ed.setInputS64(cast() minV, cast() maxV)
            case S32:
                if !hasMinMax do
                    ed.setInputS64(Swag.S32.Min, Swag.S32.Max)
                else do
                    ed.setInputS64(cast() minV, cast() maxV)
            case S64:
                if !hasMinMax do
                    ed.setInputS64(Swag.S64.Min, Swag.S64.Max)
                else do
                    ed.setInputS64(cast() minV, cast() maxV)

            case F32, F64:
                if !hasMinMax do
                    ed.setInputF64()
                else do
                    ed.setInputF64(cast() minV, cast() maxV)
            }
        }

        .refreshNative(item)

        if #isset(item.sliderBox)
        {
            item.sliderBox.sigChanged += func|prop = me, item|(ed)
            {
                prop.validateNative(item)
            }

            // Coalesce the whole drag into one undo command (see recordUndo)
            item.sliderBox.slider.sigStartChange += func|prop = me, item|(s)
            {
                prop.beginItemDrag(item)
            }
            item.sliderBox.slider.sigEndChange += func|prop = me|(s)
            {
                prop.endItemDrag()
            }
        }
        elif #isset(item.editBox)
        {
            item.editBox.sigLoseFocus += func|prop = me, item|(ed)
            {
                if ed.isValid() do
                    prop.validateNative(item)
                else do
                    ed.restoreText()
            }
        }
    }
}
