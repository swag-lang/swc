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
    Group
    Ungroup
}

// Editable text lives on FormText and (reusing it) FormCallout. The SetText undo
// treats both uniformly through these helpers instead of special-casing each type.
func formEditableText(f: IForm)->#null *String
{
    switch f
    {
    case FormText as b:    return &b.text
    case FormCallout as b: return &b.text
    }

    return null
}

func formEditableTextDirty(f: IForm)
{
    if @kindof(f) == FormText
    {
        let b = cast(*FormText) @dataof(f)
        b.isDirty = true
    }
}

// Font name/style also live on both FormText and FormCallout; the SetFont/SetFontStyle
// undos operate on either through these helpers.
func formFontNamePtr(f: IForm)->#null *String
{
    switch f
    {
    case FormText as b:    return &b.fontName
    case FormCallout as b: return &b.fontName
    }

    return null
}

func formFontStylePtr(f: IForm)->#null *FontFamilyStyle
{
    switch f
    {
    case FormText as b:    return &b.fontStyle
    case FormCallout as b: return &b.fontStyle
    }

    return null
}

// FormText caches its glyph face and must be told the font changed; FormCallout rebuilds
// its render form from live fields each paint, so it needs no explicit flag here.
func formFontDirty(f: IForm)
{
    if @kindof(f) == FormText
    {
        let b = cast(*FormText) @dataof(f)
        b.isDirtyFont = true
    }
}

struct Undo
{
    kind:     UndoKind
    capture:  #null *Capture
    baseForm: #null IForm

    selection: Array'u64

    toFreeForms: Array'IForm
    oldForms:    Array'IForm
    oldS32:      Array's32
    oldU32:      Array'u32
    oldForm:     Array'*BaseForm
    oldText:     Array'String
    oldImage:    Array'Image
    oldImg:      Image
    oldImagePos: Math.Point

    newSizeX:    s32
    newSizeY:    s32
    newPosX:     s32
    newPosY:     s32
    newImg:      Image
    newImagePos: Math.Point

    minP:      s32
    maxP:      s32
    pointIdx:  u32
    valU32:    u32
    valRef:    #null const *Swag.TypeValue
    mdlType:   #null typeinfo
    mdlValue:  #null *BaseForm
    text:      String
    fontStyle: FontFamilyStyle

    // Group/Ungroup: 'groupId' is the fresh id a Group prepends to each member;
    // 'oldGroups' is the per-selection front id an Ungroup pops (0 = was ungrouped),
    // saved so undo can prepend it back.
    groupId:   u64
    oldGroups: Array'u64
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
            let mdlType = .mdlType orelse #typeof(FormShape)
            Memory.delete(.mdlValue, mdlType)
            for f in .oldForm do
                Memory.delete(f, mdlType)
        }
    }

    mtd acceptsType(type: typeinfo)->bool
    {
        if .mdlType == null do
            return true
        let mdlType = .mdlType orelse type
        if mdlType == type do
            return true
        if mdlType == FormLine and type == FormArrow do
            return true
        return false
    }

    mtd init()
    {
        let capture = notnull .capture
        switch .kind
        {
        case RestoreOrg:
            .oldImagePos = capture.backImagePos
            .oldImg      = capture.backImg
            .oldForms    = capture.forms
            .oldS32.add(capture.width)
            .oldS32.add(capture.height)

        case Flatten:
            .selection   = capture.selection
            .oldImg      = capture.backImg
            .oldImagePos = capture.backImagePos
            .oldForms    = capture.forms

        case FlattenAll:
            .oldImg      = capture.backImg
            .oldImagePos = capture.backImagePos
            .oldForms    = capture.forms

        case SetImage:
            .oldImg      = capture.backImg
            .oldImagePos = capture.backImagePos

        case SetImageInside:
            .selection = capture.selection
            foreachSelected'FormImage(capture, .selection)
            {
                if form.kind != .Image do
                    continue
                .oldImage.add(form.image)
            }

        case Group:
            .selection = capture.selection
            .groupId   = capture.newGroupId()

        case Ungroup:
            .selection = capture.selection
            foreachSelected'BaseForm(capture, .selection)
            {
                .oldGroups.add(form.groups.isEmpty() ? 0'u64 : form.groups[0])
            }

        case SetText:
            .selection = capture.selection
            foreachSelected'BaseForm(capture, .selection)
            {
                let t = formEditableText(itf)
                if !t do
                    continue
                .oldText.add(dref t)
            }

        case SetFont:
            .selection = capture.selection
            foreachSelected'BaseForm(capture, .selection)
            {
                let np = formFontNamePtr(itf)
                let sp = formFontStylePtr(itf)
                if !np do
                    continue
                .oldText.add(dref np)
                .oldU32.add(cast(u32) dref (notnull sp))
            }

        case SetFontStyle:
            .selection = capture.selection
            foreachSelected'BaseForm(capture, .selection)
            {
                let sp = formFontStylePtr(itf)
                if !sp do
                    continue
                .oldU32.add(cast(u32) dref sp)
            }

        case SetFormFromModel:
            .selection = capture.selection
            foreachSelected'BaseForm(capture, .selection)
            {
                if !.acceptsType(@kindof(itf)) do
                    continue
                let mdlType = .mdlType orelse #typeof(FormShape)
                let save = cast(*BaseForm) notnull Memory.new(mdlType)
                itf.copy(save, form)
                .oldForm.add(save)
            }

        case AlignLeft, AlignCenter, AlignRight, AlignTop, AlignMiddle, AlignBottom:
            let horz = .kind == .AlignLeft or .kind == .AlignCenter or .kind == .AlignRight
            .selection = capture.selection
            .minP      = Swag.S32.Max
            .maxP      = Swag.S32.Min
            .oldS32.reserve(.selection.count)
            foreachSelected'BaseForm(capture, .selection)
            {
                let r = itf.boundRect()

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
            .selection = capture.selection

        case SetTypedValue:
            .selection = capture.selection
            foreachSelected'BaseForm(capture, .selection)
            {
                if !.acceptsType(@kindof(itf)) do
                    continue
                var val: u32
                Reflection.getFieldValue(&val, .valRef, form, true)
                .oldU32.add(val)
            }

        case ResetRotation:
            .selection = capture.selection
            foreachSelected'BaseForm(capture, .selection)
            {
                if !itf.canRotate() do
                    continue
                .oldU32.add(cast #bit (u32) form.rotate)
            }

        case MoveToFront, MoveToBack, MoveBackward, MoveForward:
            .selection = capture.selection
            .oldForms  = capture.forms
            .selection.sort()

        case DeleteSelection:
            .selection = capture.selection
            .oldForms  = capture.forms
        }
    }

    mtd doIt()
    {
        mtd removeSelection()
        {
            let capture = notnull .capture
            .toFreeForms.clear()
            .selection.sort()
            var offset = 0
            for s in .selection
            {
                let f = capture.forms[s - offset]
                offset += 1
                capture.forms.removeOrdered(f)
                .toFreeForms.add(f)
            }

            capture.selection.clear()
            capture.selectionHasChanged()
        }

        // Move one form to another z-order slot, keeping the selection in sync.
        // Shared by the four MoveToFront/MoveToBack/MoveForward/MoveBackward cases.
        mtd reorderForm(srcIdx, dstIdx: u64)
        {
            if srcIdx == dstIdx do
                return
            let capture = notnull .capture
            let form = capture.forms[srcIdx]
            capture.forms.removeAtOrdered(srcIdx)
            capture.forms.insertAt(dstIdx, form)
            capture.selection.remove(srcIdx)
            capture.selection.add(dstIdx)
        }

        let capture = notnull .capture

        #[Swag.Complete]
        switch .kind
        {
        case RestoreOrg:
            with capture
            {
                me.toFreeForms = .forms
                .backImg       = .backImgOriginal
                .width         = .widthOrg
                .height        = .heightOrg
                .selection.clear()
                .forms.clear()
                .dirtyBackImg = true
                .backImagePos.clear()
                .selectionHasChanged()
            }

        case Flatten:
            with capture
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
            with capture
            {
                .backImg = capture.toImage()
                .backImagePos.clear()
                me.toFreeForms = .forms
                .selection.clear()
                .forms.clear()
                .dirtyBackImg = true
                .selectionHasChanged()
            }

        case SetImage:
            capture.backImg      = .newImg
            capture.backImagePos = .newImagePos
            capture.dirtyBackImg = true

        case SetImageInside:
            foreachSelected'FormImage(capture, .selection)
            {
                if form.kind != .Image do
                    continue
                form.image = .newImg
                form.dirty = true
            }

        case Group:
            foreachSelected'BaseForm(capture, .selection)
            {
                form.groups.insertAt(0, .groupId)
            }

            capture.selectionHasChanged()

        case Ungroup:
            foreachSelected'BaseForm(capture, .selection)
            {
                if !form.groups.isEmpty() do
                    form.groups.removeAtOrdered(0)
            }

            capture.selectionHasChanged()

        case SetText:
            foreachSelected'BaseForm(capture, .selection)
            {
                let t = formEditableText(itf)
                if !t do
                    continue
                dref t = .text
                formEditableTextDirty(itf)
            }

        case SetFont:
            foreachSelected'BaseForm(capture, .selection)
            {
                let np = formFontNamePtr(itf)
                let sp = formFontStylePtr(itf)
                if !np do
                    continue
                dref np = .text
                dref (notnull sp) = .fontStyle
                formFontDirty(itf)
            }

        case SetFontStyle:
            foreachSelected'BaseForm(capture, .selection)
            {
                let sp = formFontStylePtr(itf)
                if !sp do
                    continue
                dref sp = .fontStyle
                formFontDirty(itf)
            }

        case SetFormFromModel:
            foreachSelected'BaseForm(capture, .selection)
            {
                if !.acceptsType(@kindof(itf)) do
                    continue
                if form.subKind != (notnull .mdlValue).subKind do
                    continue
                itf.copy(form, notnull .mdlValue)
            }

        case SetTypedValue:
            foreachSelected'BaseForm(capture, .selection)
            {
                if !.acceptsType(@kindof(itf)) do
                    continue
                Reflection.setFieldValue(form, .valRef, &.valU32, true)
            }

            capture.updateModelFromSelection()

        case ResetRotation:
            foreachSelected'BaseForm(capture, .selection)
            {
                if !itf.canRotate() do
                    continue
                form.rotate = 0
            }

            capture.updateModelFromSelection()

        case AlignLeft, AlignRight, AlignCenter, AlignTop, AlignBottom, AlignMiddle:
            foreachSelected'BaseForm(capture, .selection)
            {
                let r = itf.boundRect()

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
                    itf.moveBaseForm(delta - cast(s32) r.x, 0, 0, 0)
                else do
                    itf.moveBaseForm(0, delta - cast(s32) r.y, 0, 0)
            }

        case MovePoint:
            let baseForm = notnull .baseForm
            baseForm.movePoint(.pointIdx, .newPosX, .newPosY)

        case MoveBaseForm:
            let baseForm = notnull .baseForm
            baseForm.moveBaseForm(.newPosX, .newPosY, .newSizeX, .newSizeY)

        case MoveCapture:
            capture.backImagePos.x += .newPosX
            capture.backImagePos.y += .newPosY
            for f in capture.forms do
                f.moveForm(.newPosX, .newPosY)
            capture.width  += .newSizeX
            capture.height += .newSizeY
            capture.width  = Math.clamp(capture.width, Capture.MinSize, Capture.MaxSize)
            capture.height = Math.clamp(capture.height, Capture.MinSize, Capture.MaxSize)

        case OffsetSelection:
            foreachSelected'BaseForm(capture, .selection)
            {
                itf.moveForm(.newPosX, .newPosY)
            }

        case MoveToFront:
            capture.hotForm = Swag.U64.Max
            var dstIdx = capture.forms.count - 1
            for #reverse i in @countof(.selection)
            {
                .reorderForm(.selection[i], dstIdx)
                dstIdx -= 1
            }

        case MoveToBack:
            capture.hotForm = Swag.U64.Max
            var dstIdx = 0'u64
            for i in @countof(.selection)
            {
                .reorderForm(.selection[i], dstIdx)
                dstIdx += 1
            }

        case MoveForward:
            capture.hotForm = Swag.U64.Max
            for #reverse i in @countof(.selection)
            {
                let srcIdx = .selection[i]
                if srcIdx != capture.forms.count - 1 do
                    .reorderForm(srcIdx, srcIdx + 1)
            }

        case MoveBackward:
            capture.hotForm = Swag.U64.Max
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
                capture.forms.add(f)
        }

        capture.hasChanged()
    }

    mtd undoIt()
    {
        let capture = notnull .capture

        #[Swag.Complete]
        switch .kind
        {
        case RestoreOrg:
            with capture
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
            with capture
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
            capture.backImg      = .oldImg
            capture.backImagePos = .oldImagePos
            capture.dirtyBackImg = true

        case SetImageInside:
            foreachSelected'FormImage(capture, .selection)
            {
                if form.kind != .Image do
                    continue
                form.image = .oldImage[idx]
                form.dirty = true
            }

        case Group:
            foreachSelected'BaseForm(capture, .selection)
            {
                if !form.groups.isEmpty() and form.groups[0] == .groupId do
                    form.groups.removeAtOrdered(0)
            }

            capture.selectionHasChanged()

        case Ungroup:
            foreachSelected'BaseForm(capture, .selection)
            {
                if .oldGroups[idx] != 0 do
                    form.groups.insertAt(0, .oldGroups[idx])
            }

            capture.selectionHasChanged()

        case SetText:
            foreachSelected'BaseForm(capture, .selection)
            {
                let t = formEditableText(itf)
                if !t do
                    continue
                dref t = .oldText[idx]
                formEditableTextDirty(itf)
            }

        case SetFont:
            foreachSelected'BaseForm(capture, .selection)
            {
                let np = formFontNamePtr(itf)
                let sp = formFontStylePtr(itf)
                if !np do
                    continue
                dref np = .oldText[idx]
                dref (notnull sp) = cast() .oldU32[idx]
                formFontDirty(itf)
            }

        case SetFontStyle:
            foreachSelected'BaseForm(capture, .selection)
            {
                let sp = formFontStylePtr(itf)
                if !sp do
                    continue
                dref sp = cast() .oldU32[idx]
                formFontDirty(itf)
            }

        case SetFormFromModel:
            foreachSelected'BaseForm(capture, .selection)
            {
                if !.acceptsType(@kindof(itf)) do
                    continue
                if form.subKind == (notnull .mdlValue).subKind do
                    itf.copy(form, .oldForm[idx])
            }

        case SetTypedValue:
            foreachSelected'BaseForm(capture, .selection)
            {
                if !.acceptsType(@kindof(itf)) do
                    continue
                var val = .oldU32[idx]
                Reflection.setFieldValue(form, .valRef, &val, true)
            }

            capture.updateModelFromSelection()

        case ResetRotation:
            foreachSelected'BaseForm(capture, .selection)
            {
                if !itf.canRotate() do
                    continue
                form.rotate = cast #bit (f32) .oldU32[idx]
            }

            capture.updateModelFromSelection()

        case AlignLeft, AlignRight, AlignCenter, AlignTop, AlignBottom, AlignMiddle:

            // Restore through moveBaseForm: writing BaseForm.x/y directly would be a
            // no-op for the point-based forms (line, polygon, draw) whose geometry
            // lives in their points.
            let horz = .kind == .AlignLeft or .kind == .AlignRight or .kind == .AlignCenter
            foreachSelected'BaseForm(capture, .selection)
            {
                let r = itf.boundRect()
                if horz do
                    itf.moveBaseForm(.oldS32[idx] - cast(s32) r.x, 0, 0, 0)
                else do
                    itf.moveBaseForm(0, .oldS32[idx] - cast(s32) r.y, 0, 0)
            }

        case MovePoint:
            let baseForm = notnull .baseForm
            baseForm.movePoint(.pointIdx, -.newPosX, -.newPosY)

        case MoveBaseForm:
            let baseForm = notnull .baseForm
            baseForm.moveBaseForm(-.newPosX, -.newPosY, -.newSizeX, -.newSizeY)

        case MoveCapture:
            capture.backImagePos.x -= .newPosX
            capture.backImagePos.y -= .newPosY
            for f in capture.forms do
                f.moveForm(-.newPosX, -.newPosY)
            capture.width  -= .newSizeX
            capture.height -= .newSizeY

        case OffsetSelection:
            foreachSelected'BaseForm(capture, .selection)
            {
                itf.moveForm(-.newPosX, -.newPosY)
            }

        case MoveToFront, MoveToBack, MoveForward, MoveBackward, DeleteSelection:
            .toFreeForms.clear()
            capture.selection = .selection
            capture.forms     = .oldForms
            capture.selectionHasChanged()

        case CreateForm:
            .toFreeForms = .oldForms
            for .oldForms
            {
                capture.selection.remove(capture.forms.count - 1)
                capture.forms.removeBack()
            }

            capture.selectionHasChanged()
        }

        capture.hasChanged()
    }
}
