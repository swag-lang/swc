#global export

using Swag

// A double-ended queue with amortized constant-time insertion and removal at both ends.
//
// The queue owns its elements. Growth or rebalancing can invalidate every pointer, reference,
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
    // The reservation is split between both ends and does not change the queue.
    mtd reserve(newCapacity: u64)
    {
        let frontCapacity = (newCapacity + 1) / 2
        .frontItems.reserve(frontCapacity)
        .backItems.reserve(newCapacity - frontCapacity)
    }

    // Returns a mutable reference to the element at logical `index` from the front.
    mtd opIndex(index: u64)->&T
    {
        Debug.safetyBoundCheck(index < .count, "index out of range")
        if index < .frontItems.count do
            return &.frontItems[.frontItems.count - index - 1]
        return &.backItems[index - .frontItems.count]
    }

    // Returns an immutable reference to the element at logical `index` from the front.
    mtd const opIndex(index: u64)->const &T
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
        .opIndex(index) = value
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

    #[Swag.NoDoc]
    mtd ensureFrontSegment()
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

    #[Swag.NoDoc]
    mtd ensureBackSegment()
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

    // Returns a mutable reference to the front element and asserts if the queue is empty.
    mtd front()->&T
    {
        Debug.assert(.count > 0, "deque is empty")
        .ensureFrontSegment()
        return &.frontItems[.frontItems.count - 1]
    }

    // Returns an immutable reference to the front element and asserts if the queue is empty.
    mtd const front()->const &T
    {
        Debug.assert(.count > 0, "deque is empty")
        return .opIndex(0)
    }

    // Returns a mutable reference to the back element and asserts if the queue is empty.
    mtd back()->&T
    {
        Debug.assert(.count > 0, "deque is empty")
        .ensureBackSegment()
        return &.backItems[.backItems.count - 1]
    }

    // Returns an immutable reference to the back element and asserts if the queue is empty.
    mtd const back()->const &T
    {
        Debug.assert(.count > 0, "deque is empty")
        return .opIndex(.count - 1)
    }

    // Removes and returns the front element and asserts if the queue is empty.
    mtd popFront()->T
    {
        Debug.assert(.count > 0, "deque is empty")
        .ensureFrontSegment()
        .count -= 1
        return .frontItems.popBack()
    }

    // Removes and returns the back element and asserts if the queue is empty.
    mtd popBack()->T
    {
        Debug.assert(.count > 0, "deque is empty")
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
    mtd(ptr: bool) opVisit(stmt: #code(item, index: u64))
    {
        #scope(Up)
        for itemIndex in .count
        {
            var itemPtr: [*] T = undefined
            if itemIndex < .frontItems.count do
                itemPtr = .frontItems.buffer! + .frontItems.count - itemIndex - 1
            else do
                itemPtr = .backItems.buffer! + itemIndex - .frontItems.count

            #scope(Down)
            {
                #static if ptr do
                    #inject(stmt, item = cast(&T) itemPtr, index = itemIndex, break = break to Up, continue = break to Down)
                elif Reflection.isStruct(T) do
                    #inject(stmt, item = cast(const &T) itemPtr, index = itemIndex, break = break to Up, continue = break to Down)
                else do
                    #inject(stmt, item = itemPtr[0], index = itemIndex, break = break to Up, continue = break to Down)
            }
        }
    }
}
