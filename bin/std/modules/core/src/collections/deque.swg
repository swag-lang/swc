#global export

using Swag

// A double-ended queue with amortized constant-time insertion and removal at both ends.
//
// The queue owns its elements. Growth or rebalancing can invalidate every pointer
// and iterator borrowed from it. Indexed access is constant time but is intended for inspection;
// use [[Deque.pushFront]], [[Deque.pushBack]], [[Deque.popFront]], and [[Deque.popBack]] for queue work.
struct(T) Deque
{
    private
    {
        frontItems: Array'T     // Front segment in reverse logical order.
        backItems:  Array'T     // Back segment in logical order.
    }

    public readonly count: u64     // The number of elements in the queue.
}

impl Deque
{
    // Returns the number of elements in the queue.
    #[Inline]
    mtd const opCount()->u64 => .count

    // Returns whether the queue contains no elements.
    #[Inline]
    mtd const isEmpty()->bool => .count == 0

    // Returns the combined capacity of the two internal segments.
    #[Inline]
    mtd const capacity()->u64 => .frontItems.capacity + .backItems.capacity

    // Reserves combined storage for at least `newCapacity` elements.
    //
    // Existing elements are preserved. Requests at or below the current capacity, including
    // zero, do nothing. Additional storage is split between both ends.
    mtd reserve(newCapacity: u64)
    {
        if newCapacity <= .capacity() do
            return
        let frontCapacity = newCapacity / 2 + newCapacity % 2
        let backCapacity  = newCapacity - frontCapacity
        if frontCapacity > .frontItems.capacity do
            .frontItems.reserve(frontCapacity)
        if backCapacity > .backItems.capacity do
            .backItems.reserve(backCapacity)
    }

    // Returns the mutable address of the element at logical `index` from the front.
    mtd opIndexPtr(index: u64)->*T
    {
        Debug.safetyBoundCheck(index < .count, "index out of range")
        if index < .frontItems.count do
            return &.frontItems[.frontItems.count - index - 1]
        return &.backItems[index - .frontItems.count]
    }

    // Returns the address of the element at logical `index` from the front.
    mtd const opIndexPtr(index: u64)->const *T
    {
        Debug.safetyBoundCheck(index < .count, "index out of range")
        if index < .frontItems.count do
            return &.frontItems[.frontItems.count - index - 1]
        return &.backItems[index - .frontItems.count]
    }

    // Assigns a new value to the element at logical `index` from the front.
    mtd opIndexSet(index: u64, value: T)
        where Reflection.canCopy(T)
    {
        .opIndexPtr(index)[] = value
    }

    // Adds `value` at the front of the queue.
    // The value is copied; pass it with `#move` to transfer it.
    mtd pushFront(value: #fwd T)
    {
        .frontItems.add(#fwd value)
        .count += 1
    }

    // Adds `value` at the back of the queue.
    // The value is copied; pass it with `#move` to transfer it.
    mtd pushBack(value: #fwd T)
    {
        .backItems.add(#fwd value)
        .count += 1
    }

    private mtd ensureFrontSegment()
    {
        if .frontItems.count or !.backItems.count do
            return

        let sourceCount = .backItems.count
        let frontCount  = (sourceCount + 1) / 2
        var newFront: Array'T
        var newBack:  Array'T
        newFront.reserve(frontCount)
        newBack.reserve(sourceCount - frontCount)

        var index = frontCount
        while index
        {
            index -= 1
            newFront.add(#move .backItems[index])
        }

        index = frontCount
        while index < sourceCount
        {
            newBack.add(#move .backItems[index])
            index += 1
        }

        .frontItems = #move newFront
        .backItems  = #move newBack
    }

    private mtd ensureBackSegment()
    {
        if .backItems.count or !.frontItems.count do
            return

        let sourceCount = .frontItems.count
        let backCount   = (sourceCount + 1) / 2
        let frontCount  = sourceCount - backCount
        var newFront: Array'T
        var newBack:  Array'T
        newFront.reserve(frontCount)
        newBack.reserve(backCount)

        var index = frontCount
        while index
        {
            index -= 1
            newFront.add(#move .frontItems[sourceCount - index - 1])
        }

        index = frontCount
        while index < sourceCount
        {
            newBack.add(#move .frontItems[sourceCount - index - 1])
            index += 1
        }

        .frontItems = #move newFront
        .backItems  = #move newBack
    }

    // Returns a pointer to the front element and asserts if the queue is empty.
    //
    // This operation does not allocate, move elements, or invalidate existing borrows.
    mtd frontPtr()->*T
    {
        Swag.assert(.count > 0, "deque is empty")
        return .opIndexPtr(0)
    }

    // Borrows the front element for reading without copying it or changing the queue.
    //
    // Asserts if the queue is empty. Mutation of the queue can invalidate the pointer.
    mtd const frontPtr()->const *T
    {
        Swag.assert(.count > 0, "deque is empty")
        return .opIndexPtr(0)
    }

    // Returns a copy of the front element and asserts if the queue is empty.
    mtd const front()->T
    {
        Swag.assert(.count > 0, "deque is empty")
        let result: retval = .opIndexPtr(0)[]
        return result
    }

    // Returns a pointer to the back element and asserts if the queue is empty.
    //
    // This operation does not allocate, move elements, or invalidate existing borrows.
    mtd backPtr()->*T
    {
        Swag.assert(.count > 0, "deque is empty")
        return .opIndexPtr(.count - 1)
    }

    // Borrows the back element for reading without copying it or changing the queue.
    //
    // Asserts if the queue is empty. Mutation of the queue can invalidate the pointer.
    mtd const backPtr()->const *T
    {
        Swag.assert(.count > 0, "deque is empty")
        return .opIndexPtr(.count - 1)
    }

    // Returns a copy of the back element and asserts if the queue is empty.
    mtd const back()->T
    {
        Swag.assert(.count > 0, "deque is empty")
        let result: retval = .opIndexPtr(.count - 1)[]
        return result
    }

    // Removes and returns the front element and asserts if the queue is empty.
    mtd popFront()->T
    {
        Swag.assert(.count > 0, "deque is empty")
        .ensureFrontSegment()
        .count -= 1
        return .frontItems.popBack()
    }

    // Removes and returns the back element and asserts if the queue is empty.
    mtd popBack()->T
    {
        Swag.assert(.count > 0, "deque is empty")
        .ensureBackSegment()
        .count -= 1
        return .backItems.popBack()
    }

    // Removes all elements while retaining allocated storage at both ends.
    mtd clear()
    {
        .frontItems.clear()
        .backItems.clear()
        .count = 0
    }

    // Removes all elements and releases allocated storage at both ends.
    mtd free()
    {
        .frontItems.free()
        .backItems.free()
        .count = 0
    }

    // Iterates elements in logical order from front to back.
    #[Macro]
    func(ptr: bool) opVisit(const me, stmt: #code(item, index: u64))
    {
        #scope(Up)
        for itemIndex in .count
        {
            var itemPtr: const [*] T
            if itemIndex < .frontItems.count do
                itemPtr = .frontItems.buffer! + .frontItems.count - itemIndex - 1
            else do
                itemPtr = .backItems.buffer! + itemIndex - .frontItems.count

            #scope(Down)
            {
                #static if ptr do
                    #inject(stmt, item = cast(*T) itemPtr, index = itemIndex, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(T) do
                    #inject(stmt, item = cast(const *T) itemPtr, index = itemIndex, break = break to Up, continue = break to Down)
                else do
                    #inject(stmt, item = itemPtr[0], index = itemIndex, break = break to Up, continue = break to Down)
            }
        }
    }
}
