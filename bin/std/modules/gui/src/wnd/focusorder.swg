#global public

using Core

// One child being ordered, kept with its rank so an exact tie still has one answer.
private struct FocusCandidate
{
    wnd:   *Wnd = undefined     // Child being ordered.
    index: u64                  // Position in the parent's child list, the last tie break.
}

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
// - Between siblings, the order their rectangles read in — rows from top to bottom, each row
//   from left to right. The order a container *creates* its children in is not the order it
//   *places* them: a docked command bar is created before the content that fills what is left
//   over, and a stack that packs from the right hands back what it was given, reversed.
//
// Every window whose policy is [[Gui.FocusPolicy.Tab]] is a stop, wherever it sits in the tree.
// A composite is therefore one stop because it says so once and leaves its inner windows on
// [[Gui.FocusPolicy.Click]], and a tab control can be a stop for its bar while the page it shows
// keeps offering the stops of its own content. Hidden and disabled subtrees are left out
// entirely, and radio buttons sharing a group count as one stop, entered on the option that is
// checked.
struct FocusOrder
{
    public readonly
    stops: Array'(*Wnd)     // Traversal stops of the collected tree, in reading order.
}

impl FocusOrder
{
    // Collects the traversal stops of the tree rooted at `root`, `root` included.
    func collect(root: *Wnd)->FocusOrder
    {
        var result: retval
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
    mtd const indexOf(wnd: #null *Wnd)->s64
    {
        var scan = wnd
        while scan
        {
            let direct = .rank(scan)
            if direct >= 0 do
                return direct

            // A grouped radio button is not a stop unless it is the checked one, so what it
            // answers for is its own group, not the container the whole group sits in.
            let group = FocusOrder.groupRepresentative(scan!)
            if group
            {
                let rank = .rank(group)
                if rank >= 0 do
                    return rank
            }

            scan = scan.parent
        }

        return -1
    }

    // Returns the stop before or after the one `from` belongs to, wrapping around the ring.
    //
    // A `from` that belongs to no stop starts the traversal at the first stop going forward and
    // at the last one going backward, so a surface whose focus was cleared still answers Tab.
    mtd const next(from: #null *Wnd, forward = true)->#null *Wnd
    {
        let count = cast(s64) .stops.count
        if !count do
            return null

        let index = .indexOf(from)
        if index < 0 do
            return forward ? .stops[0] : .stops[cast(u64) (count - 1)]

        let step = forward ? 1's64 : count - 1
        return .stops[cast(u64) ((index + step) % count)]
    }

    // Returns the stop before or after `from` inside its own group, wrapping around that group.
    //
    // A group is the stops that share one parent: the buttons of a command bar, the options of a
    // panel, the fields a form places on one line. It is what the arrow keys walk, the way a
    // dialog box walks the controls of one group and leaves Tab to cross the whole box — so
    // Left and Right on an action bar choose between the actions instead of wandering into the
    // content above them.
    //
    // A stop alone in its group has no group to walk, and answering nothing would make the arrows
    // read as broken on exactly the surfaces that place one control per row. It falls back to the
    // full ring, which is [[Gui.FocusOrder.next]].
    mtd const nextInGroup(from: #null *Wnd, forward = true)->#null *Wnd
    {
        let index = .indexOf(from)
        if index < 0 do
            return .next(from, forward)

        let parent  = .stops[cast(u64) index].parent
        var group: Array'(*Wnd)
        var current = 0's64
        for stop in .stops where stop.parent == parent
        {
            if stop == .stops[cast(u64) index] do
                current = cast(s64) group.count
            group.add(stop)
        }

        let count = cast(s64) group.count
        if count < 2 do
            return .next(from, forward)

        let step = forward ? 1's64 : count - 1
        return group[cast(u64) ((current + step) % count)]
    }

    // Returns the first stop, or `null` when the tree holds none.
    mtd const first()->#null *Wnd => .stops.count ? .stops[0] : null

    // Returns the last stop, or `null` when the tree holds none.
    mtd const last()->#null *Wnd => .stops.count ? .stops.back() : null
}

private impl FocusOrder
{
    // Returns the position of `wnd` in the ring, or `-1` when it is not a stop of it.
    mtd const rank(wnd: #null *Wnd)->s64
    {
        for stop, index in .stops where stop == wnd do
            return cast(s64) index
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
        if !FocusOrder.isReachable(wnd) do
            return

        if wnd.isFocusStop() do
            .stops.add(wnd)

        if wnd.focusPolicy == .Inner do
            return

        // A grouped radio button that is not the one carrying its group is skipped: the group
        // already stands in the ring once, on the option that is checked.
        let ordered = FocusOrder.readingOrder(wnd)
        for child in ordered
        {
            if FocusOrder.groupRepresentative(child) do
                continue
            .addTree(child)
        }
    }

    // Reports whether the traversal may consider `wnd` and the subtree below it.
    //
    // Size is deliberately not a criterion: a container is often still unarranged when the ring
    // is asked for, and a window that means to stay out of reach says so by being hidden.
    func isReachable(wnd: *Wnd)->bool => wnd.isLocallyVisible() and wnd.isLocallyEnabled()

    // Returns the children of `wnd` in the order their rectangles read.
    func readingOrder(wnd: *Wnd)->Array'(*Wnd)
    {
        var result: retval

        var candidates: Array'FocusCandidate
        for child, index in wnd.children do
            candidates.add({child, index})

        // Top to bottom first, so the rows come out in the order they are stacked. This also
        // orders the seed of each row; the sweep below is what forms the rows themselves.
        candidates.sort(func(a, b: FocusCandidate)->s32
        {
            if a.wnd.position.y != b.wnd.position.y do
                return a.wnd.position.y < b.wnd.position.y ? -1 : 1
            if a.wnd.position.x != b.wnd.position.x do
                return a.wnd.position.x < b.wnd.position.x ? -1 : 1
            return a.index <=> b.index
        })

        // A row is what shares a band with the window that opens it: the controls of one line
        // rarely share a top edge, since a short one is centered against a taller neighbour.
        var taken: Array'bool
        taken.resize(candidates.count)

        var row: Array'FocusCandidate
        for var seed = 0'u64; seed < candidates.count; seed += 1
        {
            if taken[seed] do
                continue

            let band = candidates[seed].wnd.position
            row.clear()
            row.add(candidates[seed])
            taken[seed] = true

            for var other = seed + 1; other < candidates.count; other += 1
            {
                if taken[other] do
                    continue
                let center = candidates[other].wnd.position.vertCenter()
                if center < band.y or center >= band.bottom() do
                    continue
                row.add(candidates[other])
                taken[other] = true
            }

            row.sort(func(a, b: FocusCandidate)->s32
            {
                if a.wnd.position.x != b.wnd.position.x do
                    return a.wnd.position.x < b.wnd.position.x ? -1 : 1
                return a.index <=> b.index
            })

            for one in row do
                result.add(one.wnd)
        }

        return result
    }

    // Returns the stop a grouped radio button answers for, or `null` when `wnd` is that stop
    // itself or is not a grouped radio button at all.
    //
    // Radio buttons of one group are one stop: Tab enters the group on the option that is
    // checked, and the arrow keys move the selection inside it.
    func groupRepresentative(wnd: *Wnd)->#null *Wnd
    {
        if wnd.type != RadioButton do
            return null

        let radio = cast(*RadioButton) wnd
        if @countof(radio.groupId) == 0 or !radio.parent do
            return null

        var first: #null *Wnd
        for sibling in radio.parent.children
        {
            if sibling.type != RadioButton do
                continue
            let other = cast(*RadioButton) sibling
            if other.groupId != radio.groupId do
                continue
            if other.isChecked() do
                return sibling == wnd ? null : sibling
            first = first orelse sibling
        }

        // Nothing is checked yet: the first option carries the group, so it can still be
        // reached and answered from the keyboard.
        return first == wnd ? null : first
    }
}
