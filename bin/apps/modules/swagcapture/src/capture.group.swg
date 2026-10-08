impl Capture
{
    // Outermost group id a form belongs to (0 = ungrouped). Selecting/hit-testing a
    // grouped form expands to every form sharing this id, so a group moves as a whole.
    func formOuterGroup(f: IForm)->u64
    {
        let b = assume cast(*BaseForm, f)
        if b.groups.isEmpty() do
            return 0
        return b.groups[0]
    }

    mtd newGroupId()->u64
    {
        let id = .nextGroupId
        .nextGroupId += 1
        return id
    }

    // Grows a selection so that whenever one member of a group is selected, the entire
    // outermost group is too. Called after a click/lasso builds a raw set.
    mtd expandGroups(sel: *Array'u64)
    {
        var ids: Array'u64
        for s in sel[]
        {
            let g = formOuterGroup(.forms[s])
            if g != 0 and not ids.contains(g) do
                ids.add(g)
        }

        if ids.isEmpty() do
            return

        for f, i in .forms
        {
            let g = formOuterGroup(f)
            if g != 0 and ids.contains(g) and not sel.contains(i) do
                sel.add(i)
        }

        sel.sort()
    }

    mtd expandSelectionToGroups()
    {
        .expandGroups(&.selection)
    }

    // Grouping wraps two or more selected items into one new group; a single item has
    // nothing to combine with.
    mtd canGroup()->bool => .selection.count >= 2

    // Ungrouping applies as soon as any selected item is part of a group.
    mtd canUngroup()->bool
    {
        foreachSelected'BaseForm(me, .selection)
        {
            if formOuterGroup(itf) != 0 do
                return true
        }

        return false
    }

    // Returns whether the selection contains at least one pixel-selection form.
    mtd hasSelectedPixSel()->bool
    {
        foreachSelected'BaseForm(me, .selection)
        {
            if form.subKind == .PixSel do
                return true
        }

        return false
    }

    // Gives every distinct group id in `forms` a fresh id, keeping the relative nesting
    // structure. Used when pasting so copies form their own groups instead of silently
    // re-joining the originals (or colliding across capture files).
    mtd remapGroups(forms: Array'IForm)
    {
        var oldIds: Array'u64
        var newIds: Array'u64

        for f in forms
        {
            let b = assume cast(*BaseForm, f)
            for gid in b.groups where gid != 0 and not oldIds.contains(gid)
            {
                oldIds.add(gid)
                newIds.add(.newGroupId())
            }
        }

        for f in forms
        {
            let b = assume cast(*BaseForm, f)
            for i in b.groups.count
            {
                let idx = Slice.findLinear(oldIds.toSlice(), b.groups[i])
                if idx != Swag.U64.Max do
                    b.groups[i] = newIds[idx]
            }
        }
    }
}
