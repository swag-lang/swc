#global private

using Swag

// Heap records occupy whole host pages even when their fields need fewer bytes.
#test
{
    var allocator: Allocator
    allocator.setup()
    let before = allocator.stats().sizeCommitted
    for 32
    {
        let heap = allocator.allocateThreadHeap()
        Swag.assert(heap != null)
        Swag.assert(allocator.stats().sizeCommitted > before)
        allocator.retireThreadHeap(heap)
        Swag.assert(allocator.stats().sizeCommitted == before)
    }
}

// Bulk release must account for records belonging to heaps that were not retired.
#test
{
    var allocator: Allocator
    allocator.setup()
    let before = allocator.stats().sizeCommitted
    for 8
    {
        let heap = allocator.allocateThreadHeap()
        Swag.assert(heap != null)
    }

    allocator.releaseAll()
    Swag.assert(allocator.stats().sizeCommitted == before)
}
