impl Capture
{
    // Shows the editor's context menu at `pos`: actions on the selection first, then the clipboard,
    // arrangement, and canvas commands.
    mtd popupMenu(view: *EditView, pos: Math.Point)
    {
        with let menu = MenuCtrl.createPopup(view)
        {
            // Actions specific to the current selection. They all hide themselves
            // when they don't apply, and the trailing separator collapses when none
            // of them is visible.
            .addItem(ActionEdit.EditText)
            .addItem(ActionCopyPaste.PasteImageInside)
            .addItem(ActionEdit.ClearImageInside)
            .addSeparator()

            .addItem(ActionCopyPaste.Copy)
            .addItem(ActionCopyPaste.Cut)
            .addItem(ActionCopyPaste.Paste)
            .addSeparator()
            .addItem(ActionCopyPaste.CopyAsImage)
            .addSeparator()
            .addItem(ActionSelection.DeleteSelection)
            .addSeparator()
        }

        with let popup0 = MenuCtrl.createPopup(view)
        {
            .addItem(ActionAlign.AlignLeft)
            .addItem(ActionAlign.AlignCenter)
            .addItem(ActionAlign.AlignRight)
            .addSeparator()
            .addItem(ActionAlign.AlignTop)
            .addItem(ActionAlign.AlignMiddle)
            .addItem(ActionAlign.AlignBottom)
            menu.addPopup(appStrings().ui_MenuAlign, popup0)
        }

        with let popup1 = MenuCtrl.createPopup(view)
        {
            .addItem(ActionAlign.SendToFront)
            .addItem(ActionAlign.SendToBack)
            .addItem(ActionAlign.MoveForward)
            .addItem(ActionAlign.MoveBackward)
            menu.addPopup(appStrings().ui_MenuArrange, popup1)
        }

        with menu
        {
            .addItem(ActionGroup.Group)
            .addItem(ActionGroup.Ungroup)
            .addSeparator()
            .addItem(ActionEdit.ResetRotation)
            .addSeparator()
            .addItem(ActionSelection.SelectAll)
            .addItem(ActionSelection.SelectSameAll)
            .addItem(ActionSelection.DeSelectAll)
            .addSeparator()
            .addItem(ActionFlatten.Flatten)
            .addItem(ActionFlatten.FlattenAll)
            .addSeparator()
            .addItem(ActionSelection.Snap)
        }

        discard menu.doModal(pos)
        view.setFocus()
    }

    // Routes a pointer event on the editor.
    //
    // While no drag runs, the resize gizmo, the handles of a single selected form, and the context
    // menu answer first, and the hover follows the pointer. A left press then starts the drag the
    // current tool asks for, a left release ends it, and every event in between moves it.
    mtd mouse(view: *EditView, evt: *MouseEvent)->bool
    {
        // When a form drag/resize ends, commit the GUI refresh that hasChanged()
        // deferred during the interactive move (runs on every exit of this handler).
        defer
        {
            if evt.kind == .Released do
                me.endInteractiveMove()
        }

        var localPos = view.surfaceToLocal(evt.surfacePos)
        localPos   += view.scrollPos
        localPos.x -= .paintRect.x
        localPos.y -= .paintRect.y

        if .mouseMode == .None and .mouseHover(view, localPos, evt) do
            return true
        if .hotForm != Swag.U64.Max do
            view.app().setFrameCursor(Cursor.from(.Move))

        let pressed = evt.kind == .Pressed or evt.kind == .DoubleClick
        if .mouseMode == .None and evt.button == .Left and pressed and .startDrag(view, localPos, evt) do
            return true
        if evt.kind == .Released and evt.button == .Left do
            .finishDrag(view)

        switch #complete .mouseMode
        {
        case .None:      return false
        case .Selecting: return .dragSelection(view, localPos, evt.modifiers.has(.Control))
        case .Moving:    return .dragMove(view, localPos)
        case .Creating:  return .dragCreate(view, localPos, evt)
        }
    }

    // Lets the resize gizmo, the handles of a single selected form, and the context menu answer a
    // pointer that is not dragging, then follows it with the hover. Returns true when one of them
    // consumed the event.
    mtd mouseHover(view: *EditView, localPos: Math.Point, evt: *MouseEvent)->bool
    {
        .snapX, .snapY = -1
        if .gizmo.mouse(view, localPos, evt)
        {
            view.invalidate()
            evt.accepted = true
            if evt.kind != .Leave do
                return true
        }

        // A form edits its own handles only while it is the whole selection.
        if .selection.count == 1
        {
            let selForm = .forms[.selection[0]]
            let frozen  = view.main.freezeSel and (assume cast(*BaseForm, selForm)).freeze
            if not frozen and selForm.mouse(view, localPos, evt)
            {
                evt.accepted = true
                if evt.kind != .Leave do
                    return true
            }
        }

        if evt.kind == .Pressed and evt.button == .Right
        {
            .popupMenu(view, evt.surfacePos)
            return true
        }

        if evt.kind == .Leave
        {
            .hotForm = Swag.U64.Max
            return false
        }

        // A frozen form is out of reach while the selection is frozen.
        var hot = .hitTest(localPos)
        if hot != Swag.U64.Max and view.main.freezeSel and (assume cast(*BaseForm, .forms[hot])).freeze do
            hot = Swag.U64.Max
        if hot != .hotForm
        {
            view.invalidate()
            .hotForm = hot
        }

        return false
    }

    // Starts the drag a left press asks for: a lasso, a move of what is under the pointer, or the
    // creation of a form with the current tool. Returns true when the press was fully handled.
    mtd startDrag(view: *EditView, localPos: Math.Point, evt: *MouseEvent)->bool
    {
        // Ctrl+Shift force the selection mode
        let ctrlPressed = evt.modifiers.has(.Control)
        if (evt.modifiers.has(.Shift) and ctrlPressed) or view.main.editMode == .Selection
        {
            .beginDrag(view, .Selecting, localPos)
            .drawSelRect = true
            return false
        }

        // Double-click on a grouped form enters the group: select just that
        // child so it can be moved/edited on its own (standard "enter group").
        if evt.kind == .DoubleClick and
           .hotForm != Swag.U64.Max and
           formOuterGroup(.forms[.hotForm]) != 0
        {
            .selection.clear()
            .selection.add(.hotForm)
            .selectionHasChanged()
            .lastSelectPos = evt.surfacePos
            .beginDrag(view, .Moving, localPos)
            return true
        }

        var here = .selection.contains(.hotForm)

        // Swap between objects at the same position if no mouse move
        if .lastSelectPos.isEqualEpsilon(evt.surfacePos)
        {
            if not ctrlPressed and not .selection.isEmpty()
            {
                .selection.clear()
                .selectionHasChanged()
            }

            let result = .hitTests(localPos, false)
            .lastSelectHit += 1
            if .lastSelectHit >= result.count do
                .lastSelectHit = 0
            .hotForm = result[.lastSelectHit]
            here     = .selection.contains(.hotForm)
        }
        elif not ctrlPressed and not here and not .selection.isEmpty()
        {
            .updateModelValuesFromSelection()
            .selection.clear()
            .selectionHasChanged()
            .lastSelectHit = 0
        }

        if .hotForm == Swag.U64.Max
        {
            .beginDrag(view, .Creating, localPos)
            return false
        }

        if not here
        {
            .lastSelectPos = evt.surfacePos
            .selection.add(.hotForm)
            .expandSelectionToGroups()
            .selectionHasChanged()
        }

        .beginDrag(view, .Moving, localPos)
        return false
    }

    // Enters `mode` from `localPos`, holding the pointer until the left button is released.
    mtd beginDrag(view: *EditView, mode: MouseMode, localPos: Math.Point)
    {
        .mouseMode      = mode
        .firstMouseMove = true
        .movingStart    = localPos
        view.captureMouse()
        view.invalidate()
    }

    // Leaves the current drag and gives the pointer back.
    mtd stopDrag(view: *EditView)
    {
        view.releaseMouse()
        view.invalidate()
        .mouseMode = .None
    }

    // Ends the drag a left release closes.
    mtd finishDrag(view: *EditView)
    {
        .snapX, .snapY = -1

        if .mouseMode == .Selecting
        {
            .stopDrag(view)
            .drawSelRect = false
            view.main.updateState()
        }

        if .mouseMode == .Moving or .firstMouseMove
        {
            let wasMoving = .mouseMode == .Moving
            .stopDrag(view)

            // A body-drag move ends here (it does NOT go through GizmoRect/sigHasChanged,
            // unlike a resize). Refresh the Properties panel so x/y reflect the new
            // position, mirroring the rotate path.
            if wasMoving and view.main.propWnd != null do
                view.main.propWnd.selectionHasChanged()
        }
    }

    // Grows the lasso to `localPos` and selects every form it touches, keeping the current
    // selection when `addToSelection` is set.
    mtd dragSelection(view: *EditView, localPos: Math.Point, addToSelection: bool)->bool
    {
        .movingEnd = localPos
        var r: Math.Rectangle
        r.set(.movingStart, .movingEnd)

        // Rebuild the selection from scratch, then notify only if the set actually
        // changed: selectionHasChanged() triggers a full rebuild of the Properties
        // and QuickStyles panels, far too heavy to run on every mouse move.
        var newSel: Array'u64
        if addToSelection do
            newSel = .selection

        for f, idx in .forms
        {
            let pp = f.boundRect() * view.zoom
            if pp.intersects(r) and not newSel.contains(idx) do
                newSel.add(idx)
        }

        // Touching any group member with the lasso selects the whole group.
        .expandGroups(&newSel)

        let selChanged = not Slice.equals(newSel.toSlice(), .selection.toSlice())

        .firstMouseMove = false
        view.invalidate()
        if selChanged
        {
            .selection = newSel
            .selectionHasChanged()
        }

        return true
    }

    // Moves the selection by the offset the pointer travelled, snapped to the nearest guide.
    mtd dragMove(view: *EditView, localPos: Math.Point)->bool
    {
        let newPosX = cast(s32, (localPos.x - .movingStart.x) / view.zoom)
        let newPosY = cast(s32, (localPos.y - .movingStart.y) / view.zoom)

        let firstDragMove = .firstMouseMove
        if firstDragMove
        {
            if Math.abs(newPosX) <= 3 and Math.abs(newPosY) <= 3 do
                return true
            .firstMouseMove = false
        }

        // A body drag replays its offset from scratch on every move (undo + redo).
        // Mark the move interactive so those replays skip the full-view repaint and
        // the recent-strip refresh, exactly as GizmoRect.apply does for a resize;
        // only the region the selection leaves and enters is repainted below.
        let oldMovedBound = .getSelectionBoundRect()
        .interactiveMove = true
        if not firstDragMove do
            .undo()

        let u = .newUndo(.OffsetSelection)

        // Snap by bottom/right
        var nx = newPosX
        var ny = newPosY
        .snap(&nx, &ny, true, true)
        let saveSnapX = .snapX
        let saveSnapY = .snapY

        // Snap by top/left
        var nx1 = newPosX
        var ny1 = newPosY
        .snap(&nx1, &ny1, false, false)

        if Math.abs(nx - newPosX) > Math.abs(nx1 - newPosX)
        {
            .snapX    = saveSnapX
            u.newPosX = nx
        }
        else
        {
            u.newPosX = nx1
        }

        if Math.abs(ny - newPosY) > Math.abs(ny1 - newPosY)
        {
            .snapY    = saveSnapY
            u.newPosY = ny
        }
        else
        {
            u.newPosY = ny1
        }

        .pushUndo(u)
        .invalidateMovedRegion(oldMovedBound, .getSelectionBoundRect())
        return true
    }

    // Creates a form with the current tool on the first real move, then sizes it.
    mtd dragCreate(view: *EditView, localPos: Math.Point, evt: *MouseEvent)->bool
    {
        let newPosX = cast(s32, (localPos.x - .movingStart.x) / view.zoom)
        let newPosY = cast(s32, (localPos.y - .movingStart.y) / view.zoom)

        var createdNow = false
        if .firstMouseMove
        {
            let editView = .editView!
            if Math.abs(newPosX) <= 3 and Math.abs(newPosY) <= 3 and editView.main.editMode != .Step do
                return true
            .firstMouseMove = false
            createdNow      = true

            let mode = editView.main.getEditMode()
            let itf  = editView.main.newFormFromModel(mode, clear: true)
            itf.setup(me)
            let base = assume cast(*BaseForm, itf)
            if editView.main.editMode == .PixSel do
                base.subKind = .PixSel
            let undo = .newUndo(.CreateForm)
            undo.oldForms.add(itf)
            .pushUndo(undo)

            if itf != FormStep
            {
                .selection.clear()
                .selection.add(.forms.count - 1)
                .selectionHasChanged()
            }
        }

        let f = .forms.back()

        // The pre-edit bound must not be read on the pass that just created the
        // form: FormPolygon.boundRect() seeds a default shape while its point list
        // is still empty, and the pushUndo above has already repainted the whole
        // view anyway.
        var oldCreateBound: Math.Rectangle
        if not createdNow do
            oldCreateBound = f.boundRect()

        // Sizing the new form is as interactive as a body drag: skip the full
        // refresh hasChanged() would run on every move and repaint just the region
        // the form covered and covers. The release commits the full refresh
        // through endInteractiveMove.
        .interactiveMove = true
        if not f.edit(evt, .movingStart, localPos, view.zoom) do
            .stopDrag(view)

        // Every edit step reshapes the new form's content.
        .invalidateFormCache(f)
        .hasChanged()
        if createdNow do
            oldCreateBound = f.boundRect()
        .invalidateMovedRegion(oldCreateBound, f.boundRect())
        return true
    }

    mtd hitTest(localPos: Math.Point)->u64
    {
        // Holding `O` makes the mouse ignore every form, so a click can start a
        // lasso or create a new form on top of existing ones.
        if .editView!.app().keyboard.isKeyPressed(Input.Key.O) do
            return Swag.U64.Max
        let result = .hitTests(localPos, true)
        if result.isEmpty() do
            return Swag.U64.Max
        return result[0]
    }

    // Returns the indices of the forms under `localPos`, topmost first; only the topmost when
    // `retFirst`.
    mtd hitTests(localPos: Math.Point, retFirst: bool)->Array'u64
    {
        var result: retval
        if .forms.isEmpty() do
            return result
        let editView = .editView!
        for i in reversed(.forms.count)
        {
            let f = .forms[i]
            if not f.hitTest(localPos, editView.zoom) do
                continue
            result.add(i)
            if retFirst do
                break
        }

        return result
    }
}
