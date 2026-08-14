#global export

using Swag

// A binary-heap priority queue whose comparator selects the element returned first.
//
// A comparator returns a negative value when its left operand has higher priority than its right
// operand. Call [[PriorityQueue.initialize]] before the first operation to select the ordering
// explicitly. Growth can invalidate every pointer borrowed from the queue.
struct(T) PriorityQueue
{
    private
    {
        items:      Array'T
        comparator: #null *void
    }

    public readonly count: u64     // The number of elements in the queue.
}

impl PriorityQueue
{
    // Creates an empty priority queue that uses `comparator` to order elements.
    func create(comparator: func(const *T, const *T)->s32)->PriorityQueue
    {
        var result: retval
        result.initialize(comparator)
        return result
    }

    // Selects the comparator used by subsequent operations.
    // The queue must be empty so that no element was positioned by another ordering.
    mtd initialize(comparator: func(const *T, const *T)->s32)
    {
        Debug.assert(comparator != null)
        Debug.assert(.isEmpty(), "priority queue is not empty")
        .comparator = cast(*void) comparator
    }

    // Returns the number of elements in the queue.
    #[Inline]
    mtd const opCount()->u64 => .count

    // Returns whether the queue contains no elements.
    #[Inline]
    mtd const isEmpty()->bool => .count == 0

    // Returns the number of elements that fit without allocating.
    #[Inline]
    mtd const capacity()->u64 => .items.capacity

    // Reserves storage for at least `newCapacity` elements without changing the queue.
    mtd reserve(newCapacity: u64)
    {
        .items.reserve(newCapacity)
    }

    #[Swag.NoDoc]
    mtd const compareItems(left, right: T)->s32
    {
        if .comparator do
            return (cast(func(const *T, const *T)->s32) .comparator!)(&left, &right)

        Debug.assert(false, "priority queue has not been initialized with a comparator")
        return 0
    }

    // Adds `value` to the queue.
    // The value is copied; pass it with `#move` to transfer it.
    mtd push(value: #fwd T)
    {
        .items.add(#fwd value)
        .count += 1

        var child = .count - 1
        while child
        {
            let parent = (child - 1) / 2
            if .compareItems(.items[parent], .items[child]) <= 0 do
                break
            .items.swap(parent, child)
            child = parent
        }
    }

    // Returns a pointer to the highest-priority element and asserts if the queue is empty.
    // Mutating it in a way that changes its priority violates the heap ordering.
    mtd peekPtr()->*T
    {
        Debug.assert(.count > 0, "priority queue is empty")
        return &.items[0]
    }

    // Returns a copy of the highest-priority element and asserts if the queue is empty.
    mtd const peek()->T
    {
        Debug.assert(.count > 0, "priority queue is empty")
        let result: retval = .items[0]
        return result
    }

    // Removes and returns the highest-priority element and asserts if the queue is empty.
    mtd pop()->T
    {
        Debug.assert(.count > 0, "priority queue is empty")
        .items.swap(0, .count - 1)
        var result: retval = .items.popBack()
        .count -= 1

        var parent = 0'u64
        for
        {
            let left = parent * 2 + 1
            if left >= .count do
                break

            let right = left + 1
            var child = left
            if right < .count and .compareItems(.items[right], .items[left]) < 0 do
                child = right
            if .compareItems(.items[parent], .items[child]) <= 0 do
                break
            .items.swap(parent, child)
            parent = child
        }

        return result
    }

    // Removes all elements while retaining allocated storage and the selected comparator.
    mtd clear()
    {
        .items.clear()
        .count = 0
    }

    // Removes all elements and releases allocated storage.
    mtd free()
    {
        .items.free()
        .count = 0
    }
}
