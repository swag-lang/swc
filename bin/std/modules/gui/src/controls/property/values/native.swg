internal impl Properties
{
    mtd refreshNative(item: *PropertiesItem)
    {
        let typeNative = cast(const *Swag.TypeInfoNative) item.typeValue.pointedType!
        let data       = item.data

        if item.sliderBox != null
        {
            #[Swag.Mixin]
            func(T) setEd()
            {
                let p = cast(*T) data!
                item.sliderBox.slider.setValue(cast(f32) p[])
            }

            item.sliderBox.invalidate()
            switch typeNative.nativeKind
            {
            case .U8:  setEd'u8()
            case .U16: setEd'u16()
            case .U32: setEd'u32()
            case .U64: setEd'u64()
            case .S8:  setEd's8()
            case .S16: setEd's16()
            case .S32: setEd's32()
            case .S64: setEd's64()
            case .F32: setEd'f32()
            case .F64: setEd'f64()
            }

            .setEditMixed(item, item.sliderBox.edit)
        }
        elif item.editBox != null
        {
            #[Swag.Mixin]
            func(T) setEd()
            {
                let p = cast(*T) data!
                item.editBox.setText(Format.toString("%", p[]))
            }

            item.editBox.invalidate()
            switch typeNative.nativeKind
            {
            case .U8:  setEd'u8()
            case .U16: setEd'u16()
            case .U32: setEd'u32()
            case .U64: setEd'u64()
            case .S8:  setEd's8()
            case .S16: setEd's16()
            case .S32: setEd's32()
            case .S64: setEd's64()
            case .F32: setEd'f32()
            case .F64: setEd'f64()
            }

            .setEditMixed(item, item.editBox)
        }
    }

    mtd validateNative(item: *PropertiesItem)
    {
        let typeNative = cast(const *Swag.TypeInfoNative) item.typeValue.pointedType!
        let data       = item.data

        if item.sliderBox != null
        {
            #[Swag.Mixin]
            func(T) setEd()
            {
                var p = cast(*T) data!
                p[] = cast(T) item.sliderBox.slider.value()
            }

            switch typeNative.nativeKind
            {
            case .U8:  setEd'u8()
            case .U16: setEd'u16()
            case .U32: setEd'u32()
            case .U64: setEd'u64()
            case .S8:  setEd's8()
            case .S16: setEd's16()
            case .S32: setEd's32()
            case .S64: setEd's64()
            case .F32: setEd'f32()
            case .F64: setEd'f64()
            }
        }
        elif item.editBox != null
        {
            #[Swag.Mixin]
            func(T) setEd()
            {
                var p = cast(*T) data!
                p[] = catch StrConv.toNum'T(txt)
            }

            let txt = item.editBox.text()
            switch typeNative.nativeKind
            {
            case .U8:  setEd'u8()
            case .U16: setEd'u16()
            case .U32: setEd'u32()
            case .U64: setEd'u64()
            case .S8:  setEd's8()
            case .S16: setEd's16()
            case .S32: setEd's32()
            case .S64: setEd's64()
            case .F32: setEd'f32()
            case .F64: setEd'f64()
            }
        }

        .commitItemChange(item)
    }

    // Panel row: a full-width self-labeled composite (labeled slider or labeled edit box)
    mtd constructNativePanel(item: *PropertiesItem, value: Swag.TypeValue, typeNative: const *Swag.TypeInfoNative)
    {
        var dispName = itemDisplayName(value)

        if Reflection.hasAttribute(value, .SliderMinMax)
        {
            with let slider = SliderCtrl.create(item.line, dispName.toString())
            {
                .anchorStyle = .Right

                // Enough for a 3-4 digit value plus a unit; a bigger box would eat the track.
                .setLayoutMetrics(60, 64)
                .setAutomaticValueWidth(false)
            }

            item.assignSliderBox(slider)

            let unit = Reflection.attributeValue(value, .Unit, "value")
            if unit != null do
                slider.edit.setUnit(attributeText(unit))

            let minV = cast(f32) Reflection.attributeValue(value, .SliderMinMax, "min")!
            let maxV = cast(f32) Reflection.attributeValue(value, .SliderMinMax, "max")!

            // Whole bounds read as an integer slider (no trailing decimals), even for a
            // float field whose values are conceptually whole (a size, an angle...).
            let whole = minV == Math.floor(minV) and maxV == Math.floor(maxV)

            switch typeNative.nativeKind
            {
            case .U8, .U16, .U32, .U64:
                slider.setUnsignedBounds(cast() minV, cast() maxV)

            case .S8, .S16, .S32, .S64:
                slider.setSignedBounds(cast() minV, cast() maxV)

            case .F32, .F64:
                if whole do
                    slider.setSignedBounds(cast() minV, cast() maxV)
                else do
                    slider.setFloatBounds(minV, maxV)
            }

            return
        }

        with let ctrl = EditCtrl.create(item.line, dispName.toString(), "", flags: .ReleaseFocusOnEnterOrEscape)
        {
            .anchorStyle = .Right
            .setLayoutMetrics(.labelWidth, 0)
        }

        let unit = Reflection.attributeValue(value, .Unit, "value")
        if unit != null do
            ctrl.edit.setUnit(attributeText(unit))

        item.assignEditBox(ctrl.edit)

        var minV, maxV: s64
        var hasMinMax = false
        if Reflection.hasAttribute(value, .MinMax)
        {
            hasMinMax = true
            minV      = cast(s64) Reflection.attributeValue(value, .MinMax, "min")!
            maxV      = cast(s64) Reflection.attributeValue(value, .MinMax, "max")!
        }

        switch typeNative.nativeKind
        {
        case .U8, .U16, .U32, .U64:
            if !hasMinMax do
                ctrl.edit.setUnsignedIntegerRange()
            else do
                ctrl.edit.setUnsignedIntegerRange(cast() minV, cast() maxV)

        case .S8, .S16, .S32, .S64:
            if !hasMinMax do
                ctrl.edit.setSignedIntegerRange()
            else do
                ctrl.edit.setSignedIntegerRange(cast() minV, cast() maxV)

        case .F32, .F64:
            if !hasMinMax do
                ctrl.edit.setFloatingPointRange()
            else do
                ctrl.edit.setFloatingPointRange(cast() minV, cast() maxV)
        }
    }

    mtd constructNative(value: Swag.TypeValue, typeNative: const *Swag.TypeInfoNative, data: *u8?, parentItem: *PropertiesItem?)
    {
        let item = .addItem(value, data, parentItem)

        if .kind == .Panel
        {
            if item.label != null do
                item.label.hide()
            .constructNativePanel(item, value, typeNative)
        }
        elif Reflection.hasAttribute(value, .SliderMinMax)
        {
            var editWidth = cast(f32) Reflection.attributeValue(value, me.EditSize, "size", me.editorWidth)
            if !me.isGridLike() do
                editWidth = me.listContentWidthFromUseful(editWidth)
            with let slider = SliderCtrl.create(item.line, null)
            {
                .setLayoutMetrics(0, .valueWidth, .spacing)
                .maxSize.x = editWidth
                if me.isGridLike() do
                    .dockStyle = .CenterKeepSizeVert
                else do
                    // Fixed edit width: an anchored width would drift with the resize
                    // history and break the right-edge alignment across editors
                    .preferredSize.x = editWidth
            }

            me.adaptCondensedControl(slider)
            me.flattenCondensedEdit(slider.edit!)
            item.assignSliderBox(slider)

            let unit = Reflection.attributeValue(value, .Unit, "value")
            if unit != null do
                slider.edit.setUnit(attributeText(unit))

            let minV = cast(f32) Reflection.attributeValue(value, .SliderMinMax, "min")!
            let maxV = cast(f32) Reflection.attributeValue(value, .SliderMinMax, "max")!

            switch typeNative.nativeKind
            {
            case .U8, .U16, .U32, .U64: slider.setUnsignedBounds(cast() minV, cast() maxV)
            case .S8, .S16, .S32, .S64: slider.setSignedBounds(cast() minV, cast() maxV)
            case .F32, .F64:            slider.setFloatBounds(minV, maxV)
            }
        }
        else
        {
            let unit      = Reflection.attributeValue(value, .Unit, "value")
            var editWidth = cast(f32) Reflection.attributeValue(value, me.EditSize, "size", me.editorWidth)
            if !me.isGridLike() do
                editWidth = me.listContentWidthFromUseful(editWidth)

            with let ed = EditBox.create(item.line, value.name)
            {
                if unit != null do
                    .setUnit(attributeText(unit))
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
                minV      = cast(s64) Reflection.attributeValue(value, .MinMax, "min")!
                maxV      = cast(s64) Reflection.attributeValue(value, .MinMax, "max")!
            }

            item.assignEditBox(ed)
            switch typeNative.nativeKind
            {
            case .U8:
                if !hasMinMax do
                    ed.setUnsignedIntegerRange(Swag.U8.Min, Swag.U8.Max)
                else do
                    ed.setUnsignedIntegerRange(cast() minV, cast() maxV)

            case .U16:
                if !hasMinMax do
                    ed.setUnsignedIntegerRange(Swag.U16.Min, Swag.U16.Max)
                else do
                    ed.setUnsignedIntegerRange(cast() minV, cast() maxV)

            case .U32:
                if !hasMinMax do
                    ed.setUnsignedIntegerRange(Swag.U32.Min, Swag.U32.Max)
                else do
                    ed.setUnsignedIntegerRange(cast() minV, cast() maxV)

            case .U64:
                if !hasMinMax do
                    ed.setUnsignedIntegerRange(Swag.U64.Min, Swag.U64.Max)
                else do
                    ed.setUnsignedIntegerRange(cast() minV, cast() maxV)

            case .S8:
                if !hasMinMax do
                    ed.setSignedIntegerRange(Swag.S8.Min, Swag.S8.Max)
                else do
                    ed.setSignedIntegerRange(cast() minV, cast() maxV)

            case .S16:
                if !hasMinMax do
                    ed.setSignedIntegerRange(Swag.S16.Min, Swag.S16.Max)
                else do
                    ed.setSignedIntegerRange(cast() minV, cast() maxV)

            case .S32:
                if !hasMinMax do
                    ed.setSignedIntegerRange(Swag.S32.Min, Swag.S32.Max)
                else do
                    ed.setSignedIntegerRange(cast() minV, cast() maxV)

            case .S64:
                if !hasMinMax do
                    ed.setSignedIntegerRange(Swag.S64.Min, Swag.S64.Max)
                else do
                    ed.setSignedIntegerRange(cast() minV, cast() maxV)

            case .F32, .F64:
                if !hasMinMax do
                    ed.setFloatingPointRange()
                else do
                    ed.setFloatingPointRange(cast() minV, cast() maxV)
            }
        }

        .refreshNative(item)

        if item.sliderBox != null
        {
            item.sliderBox.sigChanged += func|prop = me, item|(ed) { prop.validateNative(item) }

            // Coalesce the whole drag into one undo command (see recordUndo)
            item.sliderBox.slider.sigStartChange += func|prop = me, item|(s) { prop.beginItemDrag(item) }
            item.sliderBox.slider.sigEndChange   += func|prop = me|(s) { prop.endItemDrag() }
        }
        elif item.editBox != null
        {
            item.editBox.sigFocusLost += func|prop = me, item|(ed)
            {
                if ed.isValid() do
                    prop.validateNative(item)
                else do
                    ed.restoreOriginalText()
            }
        }
    }
}
