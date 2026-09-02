#global public

using Core

// Inclusive range of selected indices.
struct SelRange
{
    public
    {
        start: u32     // First selected index.
        end:   u32     // Last selected index.
    }
}

// Maintains a set of selected indices as sorted, disjoint ranges.
struct SelModel
{
    internal rangesStorage: Array'SelRange
}

impl SelModel
{
    // Returns a read-only view of the selected ranges in ascending order.
    mtd const ranges()->const [..] SelRange => .rangesStorage.toSlice()

    // Returns the number of selected ranges.
    mtd const rangeCount()->u64 => .rangesStorage.count

    // Returns the index of the range containing `index`, or `Swag.U32.Max` when unselected.
    mtd const rangeIndexContaining(index: u32)->u32
    {
        for &range, rangeIndex in .rangesStorage
        {
            if index < range.start do
                break
            if index <= range.end do
                return cast(u32) rangeIndex
        }

        return Swag.U32.Max
    }

    #[Swag.Inline]
    {
        // Reports whether no index is selected.
        mtd const isEmpty()->bool => .rangesStorage.isEmpty()

        // Reports whether `index` is selected.
        mtd const isSelected(index: u32)->bool => .rangeIndexContaining(index) != Swag.U32.Max
    }

    // Returns the number of selected indices.
    mtd const selectedCount()->u64
    {
        var result: u64
        for &range in .rangesStorage do
            result += cast(u64) range.end - range.start + 1
        return result
    }

    // Removes every selected range.
    mtd clear()
    {
        .rangesStorage.clear()
    }

    // Selects one index.
    mtd select(index: u32)
    {
        .selectRange(index, index)
    }

    // Unselects one index.
    mtd unselect(index: u32)
    {
        .unselectRange(index, index)
    }

    // Sets the selected state of one index.
    mtd setSelected(index: u32, selected: bool)
    {
        if selected do
            .select(index)
        else do
            .unselect(index)
    }

    // Selects the inclusive range between `first` and `last`.
    mtd selectRange(first, last: u32)
    {
        var rangeStart = Math.min(first, last)
        var rangeEnd   = Math.max(first, last)
        var insertAt: u64

        while insertAt < .rangesStorage.count
        {
            let range = .rangesStorage[insertAt]
            if cast(u64) range.end + 1 >= rangeStart do
                break
            insertAt += 1
        }

        var mergeEnd = insertAt
        while mergeEnd < .rangesStorage.count
        {
            let range = .rangesStorage[mergeEnd]
            if cast(u64) range.start > cast(u64) rangeEnd + 1 do
                break
            rangeStart = Math.min(rangeStart, range.start)
            rangeEnd   = Math.max(rangeEnd, range.end)
            mergeEnd   += 1
        }

        if insertAt == mergeEnd
        {
            .rangesStorage.insertAt(insertAt, {rangeStart, rangeEnd})
            return
        }

        .rangesStorage[insertAt] = {rangeStart, rangeEnd}
        if mergeEnd > insertAt + 1 do
            .rangesStorage.removeAtOrdered(insertAt + 1, mergeEnd - insertAt - 1)
    }

    // Unselects the inclusive range between `first` and `last`.
    mtd unselectRange(first, last: u32)
    {
        let rangeStart = Math.min(first, last)
        let rangeEnd   = Math.max(first, last)
        var rangeIndex: u64

        while rangeIndex < .rangesStorage.count
        {
            let range = &.rangesStorage[rangeIndex]
            if range.end < rangeStart
            {
                rangeIndex += 1
                continue
            }

            if range.start > rangeEnd do
                break

            if rangeStart <= range.start and rangeEnd >= range.end
            {
                .rangesStorage.removeAtOrdered(rangeIndex)
                continue
            }

            if rangeStart > range.start and rangeEnd < range.end
            {
                let oldEnd = range.end
                range.end = rangeStart - 1
                .rangesStorage.insertAt(rangeIndex + 1, {rangeEnd + 1, oldEnd})
                break
            }

            if rangeStart <= range.start
            {
                range.start = rangeEnd + 1
                break
            }

            range.end  = rangeStart - 1
            rangeIndex += 1
        }
    }

    // Block parameters: `item` is the selected index and `index` its selection ordinal.
    #[Swag.Macro]
    mtd(ptr: bool) const opVisit(stmt: #code(item, index: u64))
    {
        // The ordinal runs across every range, and moves before the body so that a
        // 'continue' in it cannot skip the step.
        var ordinal = 0'u64

        #scope(Up)
        for &range in .rangesStorage
        {
            for itemIndex in range.start to range.end
            {
                let current = ordinal
                ordinal += 1
                #inject(stmt, item = itemIndex, index = current, break = break to Up)
            }
        }
    }
}
