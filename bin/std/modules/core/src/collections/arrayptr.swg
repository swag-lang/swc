#global export

using Swag

// A growable array of pointers that owns the objects they point to.
//
// It extends [[Core.Array]] with the allocation and deletion of the pointed-to objects, which all
// come from the array's allocator. Dropping or clearing the array deletes every object it holds.
struct(T) ArrayPtr
{
    public using base: Array'(*T?)     // Embedded base state.
}

impl ArrayPtr
{
    // Deletes every pointed-to object.
    mtd opDrop()
    {
        ArrayPtr.clear(me)
    }

    #static if Reflection.canCopy(T)
    {
        // Gives a copied array its own copy of every pointed-to object; null pointers stay null.
        //
        // An element that owns a release states no copy of its own, and nothing here can duplicate
        // what it owns: the array then states none either, and is handed over with '#move'.
        mtd opPostCopy()
        {
            if not .count do
                return
            let buffer = .storage()
            for i in .count
            {
                let oldPtr = buffer[i]
                if not oldPtr
                {
                    buffer[i] = null
                    continue
                }

                let newPtr = Memory.new'T(.allocator)
                newPtr[]  = oldPtr[]
                buffer[i] = newPtr
            }
        }
    }

    // Returns whether the array holds no pointers.
    mtd const isEmpty()->bool => .count == 0

    // Deletes every pointed-to object and leaves the array empty.
    //
    // The capacity is unchanged.
    mtd clear()
    {
        for item in me do
            Memory.delete(item, .allocator)
        .count = 0
    }

    // Removes every pointer without deleting the pointed-to objects.
    //
    // Use this when ownership of the objects has been transferred elsewhere, for example into a
    // free list or a pool. The capacity is unchanged.
    mtd detachAll()
    {
        .count = 0
    }

    // Deletes the object `item` points to, without touching the array.
    //
    // `item` must come from this array's allocator, typically through [[allocate]]. A null `item`
    // does nothing.
    mtd destroy(item: *T?)
    {
        Memory.delete(item, .allocator)
    }

    // Allocates a default-initialized object from the array's allocator, without adding it to the array.
    mtd allocate()->*T => Memory.new'T(.allocator)

    // Allocates a default-initialized object, appends its pointer, and returns it.
    mtd addNew()->*T
    {
        let ptr = .allocate()
        .add(ptr)
        return ptr
    }

    // Allocates a default-initialized object, inserts its pointer at `index`, and returns it.
    mtd insertNew(index: u64)->*T
    {
        let ptr = .allocate()
        .insertAt(index, ptr)
        return ptr
    }

    // Returns the first pointer, or null when the array is empty.
    mtd const first()->*T?
    {
        if .isEmpty() do
            return null
        return .storage()[0]
    }

    // Returns the last pointer, or null when the array is empty.
    mtd const last()->*T?
    {
        if .isEmpty() do
            return null
        return .storage()[.count - 1]
    }

    // Returns the index of the first pointer equal to `item`, or `Swag.U64.Max` when it is absent.
    //
    // Pointers are compared by address, not by the objects they point to.
    mtd const indexOf(item: *T?)->u64 => Slice.findLinear(.toSlice(), item)

    // Returns whether the array holds `item`, compared by address.
    mtd const contains(item: *T?)->bool => .indexOf(item) != Swag.U64.Max

    // Deletes the `num` objects starting at `index` and removes their pointers, preserving the order of the rest.
    //
    // Use [[Core.Array.removeAtOrdered]] to remove the pointers without deleting the objects.
    mtd deleteAt(index: u64, num: u64 = 1)
    {
        // Check the range before deleting anything: a bad index must not free unrelated objects.
        Debug.safetyBoundCheck(index + num <= .count, "index out of range")
        let buffer = .storage()
        for i in num do
            Memory.delete(buffer[index + i], .allocator)
        .removeAtOrdered(index, num)
    }

    // Deletes the object at `index` and moves the last pointer into its place.
    //
    // The order of the remaining pointers is not preserved. Use [[Core.Array.removeAt]] to remove
    // the pointer without deleting the object.
    mtd deleteAtUnordered(index: u64)
    {
        Debug.safetyBoundCheck(index < .count, "index out of range")
        let buffer = .storage()
        Memory.delete(buffer[index], .allocator)
        .removeAt(index)
    }

    // Deletes the last object and removes its pointer.
    //
    // Does nothing when the array is empty. Use [[Core.Array.popBack]] or [[Core.Array.removeBack]]
    // to remove the pointer without deleting the object.
    mtd deleteBack()
    {
        if .isEmpty() do
            return
        let buffer = .storage()
        Memory.delete(buffer[.count - 1], .allocator)
        .removeBack()
    }
}
