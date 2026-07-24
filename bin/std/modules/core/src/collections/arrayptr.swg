#global export

using Swag

// A specialized dynamic array for holding and owning pointers.
// This struct extends the base 'Array' to correctly manage the lifecycle
// (allocation and deallocation) of the pointed-to objects.
struct(T) ArrayPtr
{
    using base: Array'(#null *T)
}

impl ArrayPtr
{
    // Ensures that all pointed-to objects are deallocated when the array goes out of scope.
    mtd opDrop()
    {
        ArrayPtr.clear(me)
    }

    // Handles the deep copy of the array and the objects it points to.
    // When the array is copied, new memory is allocated for each element, and the
    // content is copied over, ensuring the new array owns its own set of objects.
    mtd opPostCopy()
    {
        if !.count do
            return
        let buffer = notnull .buffer
        for [i] in .count
        {
            let oldPtr = buffer[i]
            if oldPtr == null
            {
                buffer[i] = null
                continue
            }

            let newPtr = Memory.new'T(.allocator)
            dref newPtr = dref oldPtr
            buffer[i]   = newPtr
        }
    }

    // Checks if the array is empty (i.e., has no elements).
    mtd isEmpty()->bool
    {
        return .count == 0
    }

    // Deallocates all objects pointed to by the elements in the array and clears the array.
    // The array's count is set to 0, but the capacity is not changed.
    mtd clear()
    {
        for item in me do
            Memory.delete(item, .allocator)
        .count = 0
    }

    // Removes all elements WITHOUT deallocating the pointed-to objects.
    // Use this when ownership of the objects has been transferred elsewhere
    // (e.g. the pointers were moved into a free list / pool).
    // The capacity is not changed.
    mtd clearNoDelete()
    {
        .count = 0
    }

    // Deallocates the memory for a single given pointer.
    // The pointer is expected to have been allocated using this array's allocator.
    mtd deletePtr(item: #null *T)
    {
        Memory.delete(item, .allocator)
    }

    // Allocates memory for a new object of type T using the array's allocator.
    // Returns a pointer to the newly allocated memory.
    mtd newPtr()->*T
    {
        return Memory.new'T(.allocator)
    }

    // Allocates a new object, adds its pointer to the end of the array, and returns the pointer.
    mtd addNewPtr()->*T
    {
        let ptr = .newPtr()
        .add(ptr)
        return ptr
    }

    // Allocates a new object and inserts its pointer at 'index', returning the pointer.
    mtd insertNewPtr(index: u64)->*T
    {
        let ptr = .newPtr()
        .insertAt(index, ptr)
        return ptr
    }

    // Returns the first pointer in the array, or null if the array is empty.
    mtd getFirst()->#null *T
    {
        if .count == 0 do
            return null
        let buffer = notnull .buffer
        return buffer[0]
    }

    // Returns the last pointer in the array, or null if the array is empty.
    mtd getLast()->#null *T
    {
        if .count == 0 do
            return null
        let buffer = notnull .buffer
        return buffer[.count - 1]
    }

    // Returns the index of the given pointer (by identity), or 'Swag.U64.Max' if not present.
    mtd indexOf(item: #null *T)->u64
    {
        if .count
        {
            let buffer = notnull .buffer
            for [i] in .count
            {
                if buffer[i] == item do
                    return i
            }
        }

        return Swag.U64.Max
    }

    // True if the given pointer (by identity) is in the array.
    mtd contains(item: #null *T)->bool
    {
        return .indexOf(item) != Swag.U64.Max
    }

    // Removes and deallocates the element at 'index' (and the 'num'-1 following it), keeping
    // the order of the remaining elements. Use removeAtOrdered to remove without deallocating.
    mtd deleteAt(index: u64, num: u64 = 1)
    {
        if num
        {
            let buffer = notnull .buffer
            for [i] in num do
                Memory.delete(buffer[index + i], .allocator)
        }

        .removeAtOrdered(index, num)
    }

    // Removes and deallocates the element at 'index' by swapping the last element into its
    // place (does not preserve order). Use removeAt to remove without deallocating.
    mtd deleteAtUnordered(index: u64)
    {
        let buffer = notnull .buffer
        Memory.delete(buffer[index], .allocator)
        .removeAt(index)
    }

    // Removes and deallocates the last element. Does nothing if the array is empty. Use
    // popBack/removeBack to remove the pointer without deallocating the pointed-to object.
    mtd deleteBack()
    {
        if .count == 0 do
            return
        let buffer = notnull .buffer
        Memory.delete(buffer[.count - 1], .allocator)
        .removeBack()
    }
}
