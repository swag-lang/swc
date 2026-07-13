enum UndoKind
{
    MoveBaseForm
    MoveCapture
    OffsetSelection
    MoveToFront
    MoveToBack
    MoveForward
    MoveBackward
    AlignLeft
    AlignCenter
    AlignRight
    AlignTop
    AlignMiddle
    AlignBottom
    MovePoint
    CreateForm
    DeleteSelection
    SetTypedValue
    ResetRotation
    SetFormFromModel
    SetText
    SetFont
    SetFontStyle
    Flatten
    FlattenAll
    RestoreOrg
    SetImage
    SetImageInside
}

struct Undo
{
    kind:            UndoKind
    capture:         *Capture
    baseForm:        IForm

    selection:       Array'u64

    toFreeForms:     Array'IForm
    oldForms:        Array'IForm
    oldS32:          Array's32
    oldU32:          Array'u32
    oldForm:         Array'*BaseForm
    oldText:         Array'String
    oldImage:        Array'Image
    oldImg:          Image
    oldImagePos:     Math.Point

    newSizeX:        s32
    newSizeY:        s32
    newPosX:         s32
    newPosY:         s32
    newImg:          Image
    newImagePos:     Math.Point

    minP:            s32
    maxP:            s32
    pointIdx:        u32
    valU32:          u32
    valRef:          const *Swag.TypeValue
    mdlType:         typeinfo
    mdlValue:        *BaseForm
    text:            String
    fontStyle:       FontFamilyStyle
}

// Undo is a command of the generic gui UndoManager (owned by Capture): redo re-applies the
// action, undo reverts it. The per-kind logic lives in doIt/undoIt below.
impl IUndoCommand for Undo
{
    mtd impl redo()
    {
        .doIt()
    }

    mtd impl undo()
    {
        .undoIt()
    }
}

impl Undo
{
    mtd opDrop()
    {
        Capture.freeForms(.toFreeForms)

        if .kind == .SetFormFromModel
        {
            Memory.delete(.mdlValue, .mdlType)
            for f in .oldForm do
                Memory.delete(f, .mdlType)
        }
    }

    mtd acceptsType(type: typeinfo)->bool
    {
        if .mdlType == null do
            return true
        if .mdlType == type do
            return true
        if .mdlType == FormLine and type == FormArrow do
            return true
        return false
    }

    mtd init()
    {
        switch .kind
        {
        case RestoreOrg:
            .oldImagePos = .capture.backImagePos
            .oldImg      = .capture.backImg
            .oldForms    = .capture.forms
            .oldS32.add(.capture.width)
            .oldS32.add(.capture.height)

        case Flatten:
            .selection   = .capture.selection
            .oldImg      = .capture.backImg
            .oldImagePos = .capture.backImagePos
            .oldForms    = .capture.forms

        case FlattenAll:
            .oldImg      = .capture.backImg
            .oldImagePos = .capture.backImagePos
            .oldForms    = .capture.forms

        case SetImage:
            .oldImg      = .capture.backImg
            .oldImagePos = .capture.backImagePos

        case SetImageInside:
            .selection = .capture.selection
            for s in .selection
            {
                let f = .capture.forms[s]
                if @kindof(f) != FormImage do
                    continue
                let b = cast(*FormImage) @dataof(f)
                if b.kind != .Image do
                    continue
                .oldImage.add(b.image)
            }

        case SetText:
            .selection = .capture.selection
            for s in .selection
            {
                let f = .capture.forms[s]
                if @kindof(f) != FormText do
                    continue
                let b = cast(*FormText) @dataof(f)
                .oldText.add(b.text)
            }

        case SetFont:
            .selection = .capture.selection
            for s in .selection
            {
                let f = .capture.forms[s]
                if @kindof(f) != FormText do
                    continue
                let b = cast(*FormText) @dataof(f)
                .oldText.add(b.fontName)
                .oldU32.add(cast(u32) b.fontStyle)
            }

        case SetFontStyle:
            .selection = .capture.selection
            for s in .selection
            {
                let f = .capture.forms[s]
                if @kindof(f) != FormText do
                    continue
                let b = cast(*FormText) @dataof(f)
                .oldU32.add(cast(u32) b.fontStyle)
            }

        case SetFormFromModel:
            .selection = .capture.selection
            for s in .selection
            {
                let f = .capture.forms[s]
                if !.acceptsType(@kindof(f)) do
                    continue
                let save = cast(*BaseForm) Memory.new(.mdlType)
                f.copy(save, cast(*BaseForm) @dataof(f))
                .oldForm.add(save)
            }

        case AlignLeft, AlignCenter, AlignRight, AlignTop, AlignMiddle, AlignBottom:
            let horz = .kind == .AlignLeft or .kind == .AlignCenter or .kind == .AlignRight
            .selection = .capture.selection
            .minP      = Swag.S32.Max
            .maxP      = Swag.S32.Min
            .oldS32.reserve(.selection.count)
            for s in .selection
            {
                let f = .capture.forms[s]
                let r = f.boundRect()

                var pos, size: s32
                if horz
                {
                    pos  = cast(s32) r.x
                    size = cast(s32) r.width
                }
                else
                {
                    pos  = cast(s32) r.y
                    size = cast(s32) r.height
                }

                .oldS32.add(pos)
                .minP = Math.min(.minP, pos)
                .maxP = Math.max(.maxP, pos + size)
            }

        case OffsetSelection:
            .selection = .capture.selection

        case SetTypedValue:
            .selection = .capture.selection
            for s in .selection
            {
                let f = .capture.forms[s]
                if !.acceptsType(@kindof(f)) do
                    continue
                var val: u32
                Reflection.getFieldValue(&val, .valRef, @dataof(f), true)
                .oldU32.add(val)
            }

        case ResetRotation:
            .selection = .capture.selection
            for s in .selection
            {
                let f = .capture.forms[s]
                if !f.canRotate() do
                    continue
                let b = cast(*BaseForm) @dataof(f)
                .oldU32.add(cast #bit (u32) b.rotate)
            }

        case MoveToFront, MoveToBack, MoveBackward, MoveForward:
            .selection = .capture.selection
            .oldForms  = .capture.forms
            .selection.sort()

        case DeleteSelection:
            .selection = .capture.selection
            .oldForms  = .capture.forms
        }
    }

    mtd doIt()
    {
        mtd removeSelection()
        {
            .toFreeForms.clear()
            .selection.sort()
            var offset = 0
            for s in .selection
            {
                let f = .capture.forms[s - offset]
                offset += 1
                .capture.forms.removeOrdered(f)
                .toFreeForms.add(f)
            }

            .capture.selection.clear()
            .capture.selectionHasChanged()
        }

        // Move one form to another z-order slot, keeping the selection in sync.
        // Shared by the four MoveToFront/MoveToBack/MoveForward/MoveBackward cases.
        mtd reorderForm(srcIdx, dstIdx: u64)
        {
            if srcIdx == dstIdx do
                return
            let form = .capture.forms[srcIdx]
            .capture.forms.removeAtOrdered(srcIdx)
            .capture.forms.insertAt(dstIdx, form)
            .capture.selection.remove(srcIdx)
            .capture.selection.add(dstIdx)
        }

        #[Swag.Complete]
        switch .kind
        {
        case RestoreOrg:
            with me.capture
            {
                me.toFreeForms = .forms
                .backImg = .backImgOriginal
                .width   = .widthOrg
                .height  = .heightOrg
                .selection.clear()
                .forms.clear()
                .dirtyBackImg = true
                .backImagePos.clear()
                .selectionHasChanged()
            }

        case Flatten:
            with me.capture
            {
                // On redo, undo has cleared capture.selection, so bake from the command's
                // OWN saved selection (the same set removeSelection deletes). Restoring it
                // here keeps toImage(onlySel) and removeSelection consistent on every replay.
                .selection = me.selection
                .backImg   = .toImage(onlySel: true)
                .backImagePos.clear()
                .dirtyBackImg = true
            }
            .removeSelection()

        case FlattenAll:
            with me.capture
            {
                .backImg = me.capture.toImage()
                .backImagePos.clear()
                me.toFreeForms = .forms
                .selection.clear()
                .forms.clear()
                .dirtyBackImg = true
                .selectionHasChanged()
            }

        case SetImage:
            .capture.backImg      = .newImg
            .capture.backImagePos = .newImagePos
            .capture.dirtyBackImg = true

        case SetImageInside:
            for s, i in .selection
            {
                let f = .capture.forms[s]
                if @kindof(f) != FormImage do
                    continue
                let b = cast(*FormImage) @dataof(f)
                if b.kind != .Image do
                    continue
                b.image = .newImg
                b.dirty = true
            }

        case SetText:
            for s, i in .selection
            {
                let f = .capture.forms[s]
                if @kindof(f) != FormText do
                    continue
                let b = cast(*FormText) @dataof(f)
                b.text    = .text
                b.isDirty = true
            }

        case SetFont:
            for s, i in .selection
            {
                let f = .capture.forms[s]
                if @kindof(f) != FormText do
                    continue
                let b = cast(*FormText) @dataof(f)
                b.fontName    = .text
                b.fontStyle   = .fontStyle
                b.isDirtyFont = true
            }

        case SetFontStyle:
            for s, i in .selection
            {
                let f = .capture.forms[s]
                if @kindof(f) != FormText do
                    continue
                let b = cast(*FormText) @dataof(f)
                b.fontStyle   = .fontStyle
                b.isDirtyFont = true
            }

        case SetFormFromModel:
            for s in .selection
            {
                let f = .capture.forms[s]
                if !.acceptsType(@kindof(f)) do
                    continue
                let bf = cast(*BaseForm) @dataof(f)
                if bf.subKind != .mdlValue.subKind do
                    continue
                f.copy(cast(*BaseForm) @dataof(f), .mdlValue)
            }

        case SetTypedValue:
            for s in .selection
            {
                let f = .capture.forms[s]
                if !.acceptsType(@kindof(f)) do
                    continue
                Reflection.setFieldValue(@dataof(f), .valRef, &.valU32, true)
            }

            .capture.updateModelFromSelection()

        case ResetRotation:
            for s in .selection
            {
                let f = .capture.forms[s]
                if !f.canRotate() do
                    continue
                let b = cast(*BaseForm) @dataof(f)
                b.rotate = 0
            }

            .capture.updateModelFromSelection()

        case AlignLeft, AlignRight, AlignCenter, AlignTop, AlignBottom, AlignMiddle:
            for s in .selection
            {
                let f = .capture.forms[s]
                let r = f.boundRect()

                var delta: s32
                if .kind == .AlignLeft or .kind == .AlignTop do
                    delta = .minP
                elif .kind == .AlignRight do
                    delta = .maxP - cast(s32) r.width
                elif .kind == .AlignBottom do
                    delta = .maxP - cast(s32) r.height
                elif .kind == .AlignCenter do
                    delta = (.maxP + .minP) / 2 - (cast(s32) r.width / 2)
                else do
                    delta = (.maxP + .minP) / 2 - (cast(s32) r.height / 2)

                if .kind == .AlignLeft or .kind == .AlignRight or .kind == .AlignCenter do
                    f.moveBaseForm(delta - cast(s32) r.x, 0, 0, 0)
                else do
                    f.moveBaseForm(0, delta - cast(s32) r.y, 0, 0)
            }

        case MovePoint:
            .baseForm.movePoint(.pointIdx, .newPosX, .newPosY)

        case MoveBaseForm:
            .baseForm.moveBaseForm(.newPosX, .newPosY, .newSizeX, .newSizeY)

        case MoveCapture:
            .capture.backImagePos.x += .newPosX
            .capture.backImagePos.y += .newPosY
            for f in .capture.forms do
                f.moveForm(.newPosX, .newPosY)
            .capture.width += .newSizeX
            .capture.height += .newSizeY
            .capture.width  = Math.clamp(.capture.width, Capture.MinSize, Capture.MaxSize)
            .capture.height = Math.clamp(.capture.height, Capture.MinSize, Capture.MaxSize)

        case OffsetSelection:
            for s in .selection
            {
                let f = .capture.forms[s]
                f.moveForm(.newPosX, .newPosY)
            }

        case MoveToFront:
            .capture.hotForm = Swag.U64.Max
            var dstIdx = .capture.forms.count - 1
            for #reverse i in @countof(.selection)
            {
                .reorderForm(.selection[i], dstIdx)
                dstIdx -= 1
            }

        case MoveToBack:
            .capture.hotForm = Swag.U64.Max
            var dstIdx = 0'u64
            for i in @countof(.selection)
            {
                .reorderForm(.selection[i], dstIdx)
                dstIdx += 1
            }

        case MoveForward:
            .capture.hotForm = Swag.U64.Max
            for #reverse i in @countof(.selection)
            {
                let srcIdx = .selection[i]
                if srcIdx != .capture.forms.count - 1 do
                    .reorderForm(srcIdx, srcIdx + 1)
            }

        case MoveBackward:
            .capture.hotForm = Swag.U64.Max
            for i in @countof(.selection)
            {
                let srcIdx = .selection[i]
                if srcIdx != 0 do
                    .reorderForm(srcIdx, srcIdx - 1)
            }

        case DeleteSelection:
            .removeSelection()

        case CreateForm:
            .toFreeForms.clear()
            for f in .oldForms do
                .capture.forms.add(f)
        }

        .capture.hasChanged()
    }

    mtd undoIt()
    {
        #[Swag.Complete]
        switch .kind
        {
        case RestoreOrg:
            with me.capture
            {
                me.toFreeForms.clear()
                .width   = me.oldS32[0]
                .height  = me.oldS32[1]
                .backImg = me.oldImg
                .forms   = me.oldForms
                .selection.clear()
                .dirtyBackImg = true
                .backImagePos = me.oldImagePos
                .selectionHasChanged()
            }

        case Flatten, FlattenAll:
            with me.capture
            {
                me.toFreeForms.clear()
                .backImg      = me.oldImg
                .backImagePos = me.oldImagePos
                .forms        = me.oldForms
                .selection.clear()
                .dirtyBackImg = true
                .selectionHasChanged()
            }

        case SetImage:
            .capture.backImg      = .oldImg
            .capture.backImagePos = .oldImagePos
            .capture.dirtyBackImg = true

        case SetImageInside:
            var idx = 0
            for s in .selection
            {
                let f = .capture.forms[s]
                if @kindof(f) != FormImage do
                    continue
                let b = cast(*FormImage) @dataof(f)
                if b.kind != .Image do
                    continue
                b.image = .oldImage[idx]
                b.dirty = true
                idx += 1
            }

        case SetText:
            var idx = 0
            for s in .selection
            {
                let f = .capture.forms[s]
                if @kindof(f) != FormText do
                    continue
                let b = cast(*FormText) @dataof(f)
                b.text    = .oldText[idx]
                b.isDirty = true
                idx += 1
            }

        case SetFont:
            var idx = 0
            for s in .selection
            {
                let f = .capture.forms[s]
                if @kindof(f) != FormText do
                    continue
                let b = cast(*FormText) @dataof(f)
                b.fontName    = .oldText[idx]
                b.fontStyle   = cast() .oldU32[idx]
                b.isDirtyFont = true
                idx += 1
            }

        case SetFontStyle:
            var idx = 0
            for s in .selection
            {
                let f = .capture.forms[s]
                if @kindof(f) != FormText do
                    continue
                let b = cast(*FormText) @dataof(f)
                b.fontStyle   = cast() .oldU32[idx]
                b.isDirtyFont = true
                idx += 1
            }

        case SetFormFromModel:
            var idx = 0
            for s in .selection
            {
                let f = .capture.forms[s]
                if !.acceptsType(@kindof(f)) do
                    continue
                let bf = cast(*BaseForm) @dataof(f)
                if bf.subKind == .mdlValue.subKind do
                    f.copy(cast(*BaseForm) @dataof(f), .oldForm[idx])
                idx += 1
            }

        case SetTypedValue:
            var idx = 0
            for s in .selection
            {
                let f = .capture.forms[s]
                if !.acceptsType(@kindof(f)) do
                    continue
                var val = .oldU32[idx]
                Reflection.setFieldValue(@dataof(f), .valRef, &val, true)
                idx += 1
            }
            .capture.updateModelFromSelection()

        case ResetRotation:
            var idx = 0
            for s in .selection
            {
                let f = .capture.forms[s]
                if !f.canRotate() do
                    continue
                let b = cast(*BaseForm) @dataof(f)
                b.rotate = cast #bit (f32) .oldU32[idx]
                idx += 1
            }
            .capture.updateModelFromSelection()

        case AlignLeft, AlignRight, AlignCenter, AlignTop, AlignBottom, AlignMiddle:
            // Restore through moveBaseForm: writing BaseForm.x/y directly would be a
            // no-op for the point-based forms (line, polygon, draw) whose geometry
            // lives in their points.
            let horz = .kind == .AlignLeft or .kind == .AlignRight or .kind == .AlignCenter
            for s, i in .selection
            {
                let f = .capture.forms[s]
                let r = f.boundRect()
                if horz do
                    f.moveBaseForm(.oldS32[i] - cast(s32) r.x, 0, 0, 0)
                else do
                    f.moveBaseForm(0, .oldS32[i] - cast(s32) r.y, 0, 0)
            }

        case MovePoint:
            .baseForm.movePoint(.pointIdx, -.newPosX, -.newPosY)

        case MoveBaseForm:
            .baseForm.moveBaseForm(-.newPosX, -.newPosY, -.newSizeX, -.newSizeY)

        case MoveCapture:
            .capture.backImagePos.x -= .newPosX
            .capture.backImagePos.y -= .newPosY
            for f in .capture.forms do
                f.moveForm(-.newPosX, -.newPosY)
            .capture.width -= .newSizeX
            .capture.height -= .newSizeY

        case OffsetSelection:
            for s in .selection
            {
                let f = .capture.forms[s]
                f.moveForm(-.newPosX, -.newPosY)
            }

        case MoveToFront, MoveToBack, MoveForward, MoveBackward, DeleteSelection:
            .toFreeForms.clear()
            .capture.selection = .selection
            .capture.forms     = .oldForms
            .capture.selectionHasChanged()

        case CreateForm:
            .toFreeForms = .oldForms
            for .oldForms
            {
                .capture.selection.remove(.capture.forms.count - 1)
                .capture.forms.removeBack()
            }

            .capture.selectionHasChanged()
        }

        .capture.hasChanged()
    }
}
