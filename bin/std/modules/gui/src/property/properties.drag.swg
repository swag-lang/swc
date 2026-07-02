#global public
using Core, Pixel

// Drag-and-drop reorder of array element rows, grid mode only. Wired from the container input hook
// (properties.input.swg): a left press over an array element arms a potential drag, a move past a
// small threshold promotes it to a real drag, and the release drops the element at the slot marked
// by the insertion indicator. The indicator itself is drawn by paintBackItem (properties.paint.swg)
// from dragLineItem/dragLineAtBottom; the reorder runs through moveArrayValueTo (values/array.swg),
// so it works for both static [N]T and dynamic Core.Array without changing the element count.
moduleprivate impl Properties
{
    // Pixels the pointer must travel from the press before an armed row becomes a real drag, so a
    // plain click (select / start-edit) is never mistaken for a reorder.
    const DragThreshold = 4'f32

    mtd isDragging()->bool
    {
        return .dragElem != null and .dragActive
    }

    // Left press over a row: arm a reorder if the row resolves to an editable array element (grid
    // mode only). Nothing visible happens yet — the drag only starts once the pointer moves.
    mtd dragArm(item: #null *PropertiesItem, contentPt: Math.Point)
    {
        .dragCancel()

        if !.isGridLike() or !item do
            return

        let elem = .resolveArrayElement(item)
        if !elem do
            return
        if !.canChangeItem(elem.parent) do
            return

        .dragElem   = elem
        .dragArray  = elem.parent
        .dragStart  = contentPt
        .dragActive = false
    }

    // Pointer move while armed: promote to a real drag past the threshold, then track the insertion
    // slot under the cursor. Returns true while a drag is live so the caller swallows the move.
    mtd dragUpdate(contentPt: Math.Point)->bool
    {
        if !.dragElem do
            return false

        if !.dragActive
        {
            if Math.abs(contentPt.y - .dragStart.y) < DragThreshold and
               Math.abs(contentPt.x - .dragStart.x) < DragThreshold do
                return false
            .dragActive = true
        }

        .getApp().setFrameCursor(Cursor.from(.SizeNS))
        .updateDragTarget(contentPt.y)
        .invalidate()
        return true
    }

    // Release: move the dragged element to the marked slot (a no-op when it lands on itself), then
    // clear the drag. Returns true if a live drag was consumed.
    mtd dragDrop()->bool
    {
        if !.isDragging()
        {
            .dragCancel()
            return false
        }

        let elem = .dragElem
        let idx  = .arrayElementIndex(elem)
        var dst  = cast(u64) .dragTargetGap
        if dst > idx do
            dst -= 1

        .dragCancel()
        .moveArrayValueTo(elem, dst)
        return true
    }

    mtd dragCancel()
    {
        let wasActive = .dragActive
        .dragElem         = null
        .dragArray        = null
        .dragActive       = false
        .dragLineItem     = null
        .dragLineAtBottom = false
        .dragTargetGap    = 0
        if wasActive do
            .invalidate()
    }

    // Insertion slot (0..count) under the given content-space Y: the number of element rows whose
    // vertical center is above the cursor. Uses element header centers only, so it is robust whether
    // or not struct elements are expanded into their field rows.
    mtd arrayDropGap(contentY: f32)->s32
    {
        var gap = 0
        foreach it in .items where it.parent == .dragArray and it.line.isVisible()
        {
            if contentY >= it.line.position.vertCenter() do
                gap += 1
        }
        return gap
    }

    // Recompute where the insertion indicator is drawn. For a slot before an element the line sits at
    // that element's top; for the trailing slot it sits at the bottom of the array's last visible
    // descendant row (so it reads as "after" an expanded struct element, not mid-element).
    mtd updateDragTarget(contentY: f32)
    {
        .dragTargetGap    = .arrayDropGap(contentY)
        .dragLineItem     = null
        .dragLineAtBottom = false

        var gap = 0
        foreach it in .items where it.parent == .dragArray and it.line.isVisible()
        {
            if gap == .dragTargetGap
            {
                .dragLineItem = it
                return
            }
            gap += 1
        }

        // Trailing slot: anchor to the bottom of the array subtree (last item under the array).
        let arrIdx = Slice.findLinear(.items.toSlice(), .dragArray)
        if arrIdx == Swag.U64.Max do
            return
        let lastIdx = arrIdx + cast(u64) .dragArray.numChilds
        if lastIdx < .items.count
        {
            .dragLineItem     = .items[lastIdx]
            .dragLineAtBottom = true
        }
    }
}
