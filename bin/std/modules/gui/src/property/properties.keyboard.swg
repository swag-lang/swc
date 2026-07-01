using Core, Pixel

// Keyboard navigation and edition for the property grid.
//
// Two modes share the same keyboard focus model:
//
//  - Navigation mode: the edView (PropertiesView) holds the focus and a row is
//    highlighted (selItem). Up/Down/Home/End/PageUp/PageDown move the highlight
//    over the navigable rows; Enter/F2 (or Space/Right) start editing the row;
//    Space toggles a bool; Left/Right collapse/expand a grid group.
//
//  - Edition mode: the row's editor (editbox/slider/combo) holds the focus and
//    handles its own keys (caret, Left/Right value steps, typing, ...). The
//    grid intercepts a few keys *before* the editor sees them so navigation is
//    always possible while editing: Up/Down commit and move to the next/previous
//    row (back to navigation), Enter and Escape commit and return to navigation,
//    Tab/Shift+Tab commit and start editing the next/previous editable row.
//
// The interception is done in Properties.onHookChildEvent (which the framework
// calls for every descendant event, before the editor processes it), so the
// editors need no special cooperation beyond responding to their own keys.

public impl Properties
{
    // Give the keyboard focus to the grid in navigation mode. Selects the first
    // navigable row when none is selected yet.
    mtd focusNav()
    {
        if !.edView do
            return
        // Keep the current selection (e.g. the row just clicked, even when it is a
        // header/value row); only fall back to the first row when nothing is set.
        if !.selItem do
            .setSelItem(.firstNavigable(forward: true))
        .edView.setFocus()
        .invalidate()
    }
}

moduleprivate impl Properties
{
    // Navigation-mode key handling, driven by PropertiesView.onKeyEvent (the
    // edView owns the focus while navigating).
    mtd navKeyEvent(evt: *KeyEvent)
    {
        evt.accepted = false
        if evt.kind != .KeyPressed do
            return

        // An open combo drop-down is driven here (the grid keeps the focus), so the
        // arrows move the popup selection instead of the grid rows or the page.
        if .selItem and .selItem.comboBox and .selItem.comboBox.popup
        {
            let popup = .selItem.comboBox.popup
            switch evt.key
            {
            case Up:
                popup.keyMove(-1)
            case Down:
                popup.keyMove(1)
            case Home:
                popup.keyHome()
            case End:
                popup.keyEnd()
            case Return, Space:
                popup.keyCommit()
            case Escape:
                popup.keyCancel()
            default:
                return
            }

            evt.accepted = true
            return
        }

        if !.selItem or !.isNavigable(.selItem) do
            .setSelItem(.firstNavigable(forward: true))

        switch evt.key
        {
        case Up:
            .moveSel(-1)
        case Down:
            .moveSel(1)
        case Home:
            .setSelItem(.firstNavigable(forward: true))
        case End:
            .setSelItem(.firstNavigable(forward: false))
        case PageUp:
            .pageMove(-1)
        case PageDown:
            .pageMove(1)

        case Return, F2:
            .activateSel()

        case Space:
            if .selItem and .selItem.checkBox do
                .selItem.checkBox.toggle()
            else do
                .activateSel()

        case Right:
            // A slider steps right away (and stays focused for further steps), so
            // the very first press already changes the value.
            if .selItem and .selItem.sliderBox
            {
                .selItem.sliderBox.slider.setFocus()
                .selItem.sliderBox.slider.stepBy(1)
            }
            elif .isGridLike() and .selItem and .selItem.numChilds > 0 and !.selItem.flags.has(.Expanded)
            {
                .selItem.flags.add(.Expanded)
                .updateStates()
            }
            else do
                .activateSel()

        case Left:
            if .selItem and .selItem.sliderBox
            {
                .selItem.sliderBox.slider.setFocus()
                .selItem.sliderBox.slider.stepBy(-1)
            }
            elif .isGridLike() and .selItem and .selItem.numChilds > 0 and .selItem.flags.has(.Expanded)
            {
                .selItem.flags.remove(.Expanded)
                .updateStates()
            }

        default:
            return
        }

        evt.accepted = true
    }

    // Edition-mode key interception, called from onHookChildEvent before the
    // focused editor processes the key. Returns true when the key is consumed.
    mtd editKeyEvent(evt: *KeyEvent)->bool
    {
        if !.isEditing() do
            return false

        let shift = cast(bool) (evt.modifiers & .Shift)
        let alt   = cast(bool) (evt.modifiers & .Alt)

        switch evt.key
        {
        // Alt+Up/Down are left to the editor (e.g. Alt+Down opens a combo popup).
        case Up where !alt:
            .commitEdit()
            .moveSel(-1)
            return true

        case Down where !alt:
            .commitEdit()
            .moveSel(1)
            return true

        case Return, Escape:
            .commitEdit()
            return true

        case Tab:
            .commitEdit()
            .moveSel(shift ? -1 : 1)
            .activateSel()
            return true
        }

        return false
    }

    // True when 'w' is an interactive value editor (by widget type). This covers the
    // built-in editors as well as the inner editboxes/combos/sliders used by custom
    // editors (color hex field, vector x/y/z, ...), but not labels, lines or the
    // popup-trigger icon buttons.
    mtd isEditorWnd(w: #null *Wnd)->bool
    {
        if !w do
            return false
        return w.type == EditBox or w.type == ComboBox or w.type == Slider or w.type == CheckButton
    }
}

fileprivate impl Properties
{
    // True when the grid currently has a focused row editor.
    mtd isEditing()->bool
    {
        let f = .getFocus()
        if !f or f == cast(*Wnd) .edView do
            return false
        return .isEditorWnd(f)
    }

    // First interactive editor widget inside 'wnd' (depth-first), or null. Used to
    // start edition on rows whose editor is a composite/custom control.
    mtd firstEditorIn(wnd: #null *Wnd)->#null *Wnd
    {
        if !wnd do
            return null
        foreach c in wnd.childs
        {
            if .isEditorWnd(c) do
                return c
            let sub = .firstEditorIn(c)
            if sub do
                return sub
        }

        return null
    }

    // A row is navigable when it is visible and is a real value/editor row. This
    // covers the built-in editors, rows with a custom editor (which still carry a
    // data+type, e.g. color pickers), and — in grid mode — expandable group headers
    // so they can be collapsed/expanded by keyboard. Pure section/category headers
    // (no data, no type) are skipped.
    mtd isNavigable(item: #null *PropertiesItem)->bool
    {
        if !item or !item.line do
            return false
        if !item.line.isVisible() do
            return false
        if .itemHasEditor(item) do
            return true
        if item.data != null and item.type != null do
            return true
        if .isGridLike() and item.numChilds > 0 do
            return true
        return false
    }

    mtd itemHasEditor(item: *PropertiesItem)->bool
    {
        return item.editBox != null or item.comboBox != null or item.sliderBox != null or item.checkBox != null
    }

    mtd firstNavigable(forward: bool)->#null *PropertiesItem
    {
        if forward
        {
            foreach item in .items
            {
                if .isNavigable(item) do
                    return item
            }
        }
        else
        {
            for var i = cast(s64) .items.count - 1; i >= 0; i -= 1
            {
                if .isNavigable(.items[cast(u64) i]) do
                    return .items[cast(u64) i]
            }
        }

        return null
    }

    mtd indexOfItem(item: #null *PropertiesItem)->s64
    {
        if !item do
            return -1
        foreach it, idx in .items
        {
            if it == item do
                return cast(s64) idx
        }

        return -1
    }

    // Set the selected (highlighted) row, scroll it into view and repaint.
    mtd setSelItem(item: #null *PropertiesItem)
    {
        .selItem = item
        if item do
            .ensureItemVisible(item)
        .invalidate()
    }

    // Move the selection by 'dir' (+1/-1) over the navigable rows, clamped.
    mtd moveSel(dir: s32)
    {
        if .items.isEmpty() do
            return

        let cur = .indexOfItem(.selItem)
        if cur < 0
        {
            .setSelItem(.firstNavigable(forward: dir > 0))
            return
        }

        var i = cur
        for
        {
            i += dir
            if i < 0 or i >= cast(s64) .items.count do
                return
            if .isNavigable(.items[cast(u64) i])
            {
                .setSelItem(.items[cast(u64) i])
                return
            }
        }
    }

    // Page up/down: move by roughly one viewport of rows.
    mtd pageMove(dir: s32)
    {
        let lh    = .isGridLike() ? .gridLineHeight : 40.0
        let viewH = .scrollWnd.getClientRect().height
        let count = cast(u32) Math.max(1.0, Math.floor(viewH / Math.max(lh, 1.0)))
        for count do
            .moveSel(dir)
    }

    // Start editing the selected row: focus its editor, toggle a bool in place,
    // or expand/collapse an expandable grid group.
    mtd activateSel()
    {
        let item = .selItem
        if !item do
            return

        if item.checkBox
        {
            item.checkBox.toggle()
            return
        }

        if item.editBox
        {
            item.editBox.setFocus()
            item.editBox.selectAll()
            return
        }

        if item.comboBox
        {
            // Open the drop-down so the new item is chosen from the list, rather than
            // silently cycling values in place. The grid keeps the focus and forwards
            // the keys to the popup (see navKeyEvent), so they never leave the page.
            item.comboBox.openPopup()
            return
        }

        if item.sliderBox
        {
            // Edit the value box like a plain editbox row: focus it and select its
            // text so the value can be typed over right away. The slider track stays
            // reachable through the Left/Right steps in navigation mode.
            item.sliderBox.edit.setFocus()
            item.sliderBox.edit.selectAll()
            return
        }

        if .isGridLike() and item.numChilds > 0
        {
            item.flags.toggle(.Expanded)
            .updateStates()
            return
        }

        // Custom/composite editors (color, vector, ...) don't register a named
        // editor: focus their first inner control so they can be edited too.
        let w = .firstEditorIn(item.line)
        if w do
            w.setFocus()
    }

    // Commit the current edition and return to navigation mode. Moving the focus
    // back to edView makes the editor lose focus, which runs its commit/validate
    // path (e.g. EditBox.sigLoseFocus -> validateNative).
    mtd commitEdit()
    {
        if .edView do
            .edView.setFocus()
    }

    // Scroll the grid so the given row is fully visible.
    mtd ensureItemVisible(item: *PropertiesItem)
    {
        if !item or !item.line do
            return

        let lineTop       = item.line.position.y
        let lineBottom    = item.line.position.bottom()
        let sc            = .scrollWnd.getScrollPos()
        let viewH         = .scrollWnd.getClientRect().height
        let visibleBottom = sc.y + viewH

        if lineTop >= sc.y and lineBottom <= visibleBottom do
            return

        var y = lineTop
        if lineBottom > visibleBottom do
            y = lineBottom - viewH
        .scrollWnd.setScrollPos(sc.x, y)
    }
}
