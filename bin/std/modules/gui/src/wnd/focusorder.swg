#global public

using Core

// Keyboard traversal stops of one window tree, in the order the eye reads them.
//
// The order is computed on demand instead of maintained, so a tree that has gained, lost,
// moved, hidden, or disabled a window since the last traversal needs no bookkeeping to stay
// correct.
//
// Two rules produce it:
//
// - Depth first, so a subtree is traversed whole before its next sibling. Two forms side by
//   side keep their own fields together instead of interleaving row by row.
// - Between siblings, explicit [[Gui.Wnd.tabIndex]] values come first in ascending order.
//   Automatic siblings use their rectangles, top to bottom and left to right. Ties use the
//   order the siblings joined their parent, which stays stable when their paint order changes.
//
// Every window whose policy is [[Gui.FocusPolicy.Tab]] is a stop, wherever it sits in the tree.
// A composite is therefore one stop because it says so once and declares its inner windows
// [[Gui.FocusPolicy.Inner]], and a tab control can be a stop for its bar while the page it shows
// keeps offering the stops of its own content. Hidden and disabled subtrees are left out
// entirely. A radio group occupies the place of its earliest attached option. Entering the
// group focuses its checked eligible member or the earliest eligible member.
struct FocusOrder
{
    public readonly stops: Array'(*Wnd)     // Traversal stops of the collected tree, in reading order.
}

impl FocusOrder
{
    // Collects the traversal stops of the tree rooted at `root`, `root` included.
    func collect(root: *Wnd)->FocusOrder
    {
        var result: #returntype
        result.addTree(root)
        return result
    }

    // Collects the traversal stops of the whole tree `wnd` belongs to.
    //
    // The tree is the one the structural parents lead to, which is the surface `wnd` sits on:
    // traversal never crosses from one surface to another, so a modal keeps the keyboard.
    func around(wnd: *Wnd)->FocusOrder => collect(wnd.rootWnd())

    // Returns the position of the stop `wnd` belongs to, or `-1` when it belongs to none.
    //
    // A window that is not itself a stop answers for the stop that owns it, so a focus sitting
    // on the inner editor of a composite still reports the position of the composite.
    mtd const indexOf(wnd: *Wnd?)->s64
    {
        var scan = wnd
        while scan
        {
            let direct = .rank(scan)
            if direct >= 0 do
                return direct

            if scan is RadioButton as radio where radio.groupId.count and radio.parent
            {
                for stop, index in .stops where stop.parent == radio.parent
                {
                    if stop is RadioButton as member where member.groupId == radio.groupId do
                        return cast(s64, index)
                }
            }

            scan = scan.parent
        }

        return -1
    }

    // Returns the stop before or after the one `from` belongs to, wrapping around the ring.
    //
    // A `from` that belongs to no stop starts the traversal at the first stop going forward and
    // at the last one going backward, so a surface whose focus was cleared still answers Tab.
    mtd const next(from: *Wnd?, forward = true)->*Wnd?
    {
        let count = cast(s64, .stops.count)
        if not count do
            return null

        let index = .indexOf(from)
        if index < 0 do
            return forward ? .stops[0] : .stops[cast(u64, (count - 1))]

        let step = forward ? 1's64 : count - 1
        return .stops[cast(u64, ((index + step) % count))]
    }

    // Returns the stop before or after `from` inside its own group, wrapping around that group.
    //
    // [[Gui.Wnd.arrowNavigation]] on the parent enables the group. Returns `null` when
    // `from` has no group or the group has fewer than two eligible stops.
    mtd const nextInGroup(from: *Wnd?, forward = true)->*Wnd?
    {
        let index = .indexOf(from)
        if index < 0 do
            return null

        let parent = .stops[cast(u64, index)].parent
        if not parent or not parent.arrowNavigation do
            return null
        var group: Array'(*Wnd)
        var current = 0's64
        for stop in .stops where stop.parent == parent
        {
            if stop == .stops[cast(u64, index)] do
                current = cast(s64, group.count)
            group.add(stop)
        }

        let count = cast(s64, group.count)
        if count < 2 do
            return null

        let step = forward ? 1's64 : count - 1
        return group[cast(u64, ((current + step) % count))]
    }

    // Returns the first stop, or `null` when the tree holds none.
    mtd const first()->*Wnd? => .stops.count ? .stops[0] : null

    // Returns the last stop, or `null` when the tree holds none.
    mtd const last()->*Wnd? => .stops.count ? .stops.back() : null
}

private impl FocusOrder
{
    // Returns the position of `wnd` in the ring, or `-1` when it is not a stop of it.
    mtd const rank(wnd: *Wnd?)->s64
    {
        for stop, index in .stops where stop == wnd do
            return cast(s64, index)
        return -1
    }

    // Appends the stops of `wnd`: itself when it is one, then its children in reading order.
    //
    // A stop is still walked into, because a window can be a stop and hold stops: the bar of a
    // tab control answers Tab, and so does every control of the page it shows. What ends the walk
    // is [[Gui.FocusPolicy.Inner]], which is how a composite says that everything below it is
    // parts of itself rather than controls of the surface.
    mtd addTree(wnd: *Wnd)
    {
        if not FocusOrder.isReachable(wnd) do
            return

        if wnd.isFocusStop()
        {
            let target = wnd.focusTarget()
            if target.surface == wnd.surface and target.focusPolicy != .None and target.isVisible() and target.isEnabled() do
                .stops.add(wnd)
        }

        if wnd.focusPolicy == .Inner do
            return

        for child in FocusOrder.readingOrder(wnd)
        {
            if child is RadioButton as radio where radio.groupId.count and radio.isFocusStop()
            {
                if let member = FocusOrder.groupRepresentative(radio) do
                    .addTree(member)
            }
            else do
                .addTree(child)
        }
    }

    // Reports whether the traversal may consider `wnd` and the subtree below it.
    //
    // Size is deliberately not a criterion: a container is often still unarranged when the ring
    // is asked for, and a window that means to stay out of reach says so by being hidden.
    func isReachable(wnd: *Wnd)->bool => not wnd.isPendingDestroy and wnd.isLocallyVisible() and wnd.isLocallyEnabled()

    // Finds a live window in the reachable tree, including controls that accept pointer focus but
    // are not stops in keyboard traversal. Comparing before descending never dereferences the
    // previously focused pointer unless it is still part of the current tree.
    internal func contains(root: *Wnd, target: *Wnd)->bool
    {
        if not FocusOrder.isReachable(root) do
            return false
        if root == target do
            return true

        for child in root.children where FocusOrder.contains(child, target) do
            return true
        return false
    }

    // Returns the children of `wnd` in the order their rectangles read.
    func readingOrder(wnd: *Wnd)->Array'(*Wnd)
    {
        var result: #returntype

        var explicit, candidates: Array'(*Wnd)
        for child in wnd.children
        {
            if child is RadioButton as radio where radio.groupId.count and radio.isFocusStop()
            {
                if not FocusOrder.groupRepresentative(radio) do
                    continue
            }
            elif not FocusOrder.isReachable(child) do
                continue

            if child.tabIndex >= 0 do
                explicit.add(child)
            else do
                candidates.add(child)
        }

        explicit.sort(func(a, b: *Wnd)->s32
        {
            if a.tabIndex != b.tabIndex do
                return a.tabIndex <=> b.tabIndex
            return a.tabSequence <=> b.tabSequence
        })
        for child in explicit do
            result.add(child)

        // Top to bottom first, so the rows come out in the order they are stacked.
        candidates.sort(func(a, b: *Wnd)->s32
        {
            if a.position.y != b.position.y do
                return a.position.y < b.position.y ? -1 : 1
            if a.position.x != b.position.x do
                return a.position.x < b.position.x ? -1 : 1
            return a.tabSequence <=> b.tabSequence
        })

        // A row is what shares a band with the window that opens it: the controls of one line
        // rarely share a top edge, since a short one is centered against a taller neighbour.
        var taken: Array'bool
        taken.resize(candidates.count)

        var row: Array'(*Wnd)
        for var seed = 0'u64; seed < candidates.count; seed += 1
        {
            if taken[seed] do
                continue

            let band = candidates[seed].position
            row.clear()
            row.add(candidates[seed])
            taken[seed] = true

            for var other = seed + 1; other < candidates.count; other += 1
            {
                if taken[other] do
                    continue
                let center = candidates[other].position.vertCenter()
                if center < band.y or center >= band.bottom() do
                    continue
                row.add(candidates[other])
                taken[other] = true
            }

            row.sort(func(a, b: *Wnd)->s32
            {
                if a.position.x != b.position.x do
                    return a.position.x < b.position.x ? -1 : 1
                return a.tabSequence <=> b.tabSequence
            })

            for one in row do
                result.add(one)
        }

        return result
    }

    // Only the earliest attached option places the group in the order. Its checked eligible
    // option receives the keyboard. The anchor can be hidden or disabled while the group lasts.
    func groupRepresentative(anchor: *RadioButton)->*Wnd?
    {
        if anchor.isPendingDestroy do
            return null
        let parent = anchor.parent
        if not parent do
            return null

        var first, checked: *Wnd?
        for sibling in parent.children
        {
            if sibling is RadioButton as radio where radio.groupId == anchor.groupId and radio.isFocusStop() and not radio.isPendingDestroy
            {
                if sibling.tabSequence < anchor.tabSequence do
                    return null
                if not FocusOrder.isReachable(sibling) do
                    continue
                if radio.isChecked() do
                    checked = sibling
                if not first or sibling.tabSequence < first.tabSequence do
                    first = sibling
            }
        }

        return checked orelse first
    }
}
