#global export

using Swag

// A stack-allocated array with a fixed capacity known at compile time.
// It provides a similar interface to the dynamic 'Array' but does not allocate memory on the heap.
struct(T, N: u64) StaticArray
{
    public
    {
        buffer: [N] T     // The fixed-size me.buffer that holds the elements.
        count:  u64       // The number of valid elements currently in the array.
    }
}

impl StaticArray
{
    // Returns the number of elements in the array.
    #[Inline]
    mtd opCount()->u64
    {
        return .count
    }

    // Returns a raw, constant pointer to the array's buffer.
    #[Inline]
    mtd opData()->const *T
    {
        return &.buffer[0]
    }

    // Allows the array to be implicitly cast to a mutable slice.
    #[Inline]
    mtd opCast()->[..] T
    {
        return .toSlice()
    }

    // Allows the array to be implicitly cast to an immutable slice.
    #[Inline]
    mtd const opCast()->const [..] T
    {
        return .toSlice()
    }

    // Creates a slice from a sub-part of the array.
    #[Inline]
    mtd opSlice(lower, upper: u64)->[..] T
    {
        Debug.safetyBoundCheck(lower <= upper, "lower bound greater than upper bound")
        Debug.safetyBoundCheck(lower < .count, "lower bound out of range")
        Debug.safetyBoundCheck(upper < .count, "upper bound out of range")
        return Swag.makeSlice(&.buffer[lower], (upper + 1) - lower)
    }

    // Returns the address of the element at the specified index.
    #[Inline]
    mtd const opIndexPtr(index: u64)->const *T
    {
        Debug.safetyBoundCheck(index < .count, "index out of range")
        return &.buffer[index]
    }

    // Returns the mutable address of the element at the specified index.
    #[Inline]
    mtd opIndexPtr(index: u64)->*T
    {
        Debug.safetyBoundCheck(index < .count, "index out of range")
        return &.buffer[index]
    }

    // Assigns a new value to the element at the specified index.
    #[Inline]
    mtd opIndexSet(index: u64, value: T)
        where Reflection.canCopy(T)
    {
        Debug.safetyBoundCheck(index < .count, "index out of range")
        .buffer[index] = value
    }

    // Handles compound assignment operators (e.g., `+=`, `-=`) for elements.
    #[Inline]
    mtd(op: Swag.Operator) opIndexAssign(index: u64, value: T)
    {
        Debug.safetyBoundCheck(index < .count, "index out of range")
        #ast "buffer[index] " ++ op.symbol() ++ " value"
    }

    // Replaces the content of the array with elements copied from a slice.
    // Asserts if the slice is larger than the array's capacity.
    mtd opSet(arr: const [..] T)
        where Reflection.canCopy(T)
    {
        let countof = arr.count
        if countof
        {
            let dataof = arr.buffer
            let buffer = cast([*] T) &.buffer[0]
            if dataof >= buffer and dataof < buffer + .count
            {
                var copy: Array'T
                copy.add(arr)
                .opSet(copy.toSlice())
                return
            }
        }

        .clear()
        if !countof do
            return
        Debug.assert(countof <= N, "slice is too big")
        var dataof = arr.buffer

        #static if Reflection.hasPostCopy(T)
        {
            for i in countof do
                .buffer[i] = #nodrop dataof[i]
        }
        else
        {
            Memory.copy(.buffer, dataof, #sizeof(T) * countof)
        }

        .count += countof
    }

    // Provides a way to iterate over each element in the array.
    // This is a macro that accepts a code block to execute for each element.
    // Visiting by pointer is supported.
    // Block parameters: 'item' is the element (or a pointer to it), 'index' its ordinal.
    #[Macro]
    mtd(ptr: bool) opVisit(stmt: #code(item, index: u64))
    {
        if !.count do
            return

        // Little trick to avoid labels. That way a 'continue' in the user code will work correctly
        var scan = cast([*] T) &.buffer[0] - 1

        for visitIdx in .count
        {
            scan += 1

            #static if ptr do
                #inject(stmt, item = cast(*T) scan, index = visitIdx)
            elif Reflection.isStruct(T) do
                #inject(stmt, item = cast(const *T) scan, index = visitIdx)
            else do
                #inject(stmt, item = scan[0], index = visitIdx)
        }
    }

    // Returns a zero-allocation view that traverses the elements from last to first.
    mtd reversed()->ReversedSlice'T
    {
        return reverseSlice(.toSlice())
    }

    // Returns an immutable zero-allocation view that traverses the elements from last to first.
    mtd const reversed()->ConstReversedSlice'T
    {
        return reverseSlice(.toSlice())
    }

    // Returns a zero-allocation view over adjacent elements.
    mtd const pairs()->Pairs'T
    {
        return pairsView(.toSlice())
    }

    // Drops all elements in the array, setting its me.count to 0.
    // This is equivalent to 'clear' for this type.
    mtd free()
    {
        .clear()
    }

    // Returns 'true' if the array contains no elements.
    #[Inline]
    mtd const isEmpty() => .count == 0

    // Returns a mutable slice containing all valid elements of the array.
    #[Inline]
    mtd toSlice()->[..] T
    {
        return Swag.makeSlice(&.buffer[0], .count)
    }

    // Returns an immutable slice containing all valid elements of the array.
    #[Inline]
    mtd const toSlice()->const [..] T
    {
        return Swag.makeSlice(&.buffer[0], .count)
    }

    // Changes the number of elements in the array to 'newCount'.
    // Asserts if 'newCount' exceeds the static capacity.
    mtd resize(newCount: u64)
    {
        if newCount == .count do
            return
        Debug.assert(newCount <= N, "size is too big")
        if newCount > .count
        {
            let data = cast([*] T) &.buffer[0]
            Swag.init(data + .count, newCount - .count)
            .count = newCount
        }
        else
        {
            let data         = cast([*] T) &.buffer[0]
            let droppedCount = .count - newCount
            Swag.drop(data + newCount, droppedCount)
            Swag.init(data + newCount, droppedCount)
            .count = newCount
        }
    }

    // Removes all elements from the array, setting its me.count to 0.
    // This calls the destructor for each element if one exists.
    mtd clear()
    {
        let oldCount = .count
        #static if Reflection.hasDrop(T)
        {
            for index in oldCount do
                Swag.drop(&.buffer[index])

            Swag.init(&.buffer[0], oldCount)
        }

        .count = 0
    }

    // Adds an element to the end of the array, but only if it's not already present.
    // Asserts if the array is full.
    // The value is copied; pass it with '#move' to move it instead.
    mtd addOnce(value: #fwd T)
    {
        if .contains(value) do
            return
        Debug.assert(.count != N, "the array is full")
        .buffer[.count] = #nodrop #fwd value
        .count          += 1
    }

    // Adds an element to the end of the array.
    // Asserts if the array is full. The value is copied; pass it with '#move' to move it instead.
    mtd add(value: #fwd T)
    {
        Debug.assert(.count != N, "the array is full")
        .buffer[.count] = #nodrop #fwd value
        .count          += 1
    }

    // Makes room for 'num' elements at the end of the array and returns a pointer to the new space.
    // The new memory is not initialized. Asserts if the array does not have enough capacity.
    mtd emplaceAddress(num: u32 = 1)->[*] T
    {
        Debug.assert(.count + num <= N, "the array is full")
        .count += num
        return cast([*] T) &.buffer[0] + .count - num
    }

    // Makes room for 'num' elements at the end of the array and returns a pointer to the new space.
    // The new memory is default-initialized. Asserts if the array does not have enough capacity.
    mtd emplaceInitAddress(num: u32 = 1)->[*] T
    {
        Debug.assert(.count + num <= N, "the array is full")
        .count += num
        var res = cast([*] T) &.buffer[0] + .count - num
        Swag.init(res, num)
        return res
    }

    // Inserts a value at a specific index, shifting existing elements to the right.
    // Asserts if the array is full. Order is preserved.
    // The value is copied; pass it with '#move' to move it instead.
    mtd insertAt(index: u64, value: #fwd T)
    {
        Debug.assert(index <= .count, "index out of range")
        if index == .count do
            return .add(#fwd value)
        Debug.assert(.count != N, "the array is full")
        .count += 1

        #static if Reflection.hasPostMove(T)
        {
            for var idx = .count - 1; idx > index; idx -= 1 do
                .buffer[idx] = #relocate .buffer[idx - 1]
        }
        else
        {
            Memory.copyOverlapping(&.buffer[index + 1], &.buffer[index], #sizeof(T) * (.count - 1 - index))
        }

        .buffer[index] = #nodrop #fwd value
    }

    // Inserts elements from a slice at a specific index, shifting existing elements to the right.
    // Asserts if the array does not have enough capacity. Order is preserved.
    mtd insertAt(index: u64, values: const [..] T?)
        where Reflection.canCopy(T)
    {
        var sliceCount = values.count
        if !sliceCount do
            return
        let buffer = cast([*] T) &.buffer[0]
        let dataof = values.buffer
        if dataof >= buffer and dataof < buffer + .count
        {
            var copy: Array'T
            copy.add(values)
            return .insertAt(index, copy.toSlice())
        }

        Debug.assert(index <= .count, "index out of range")
        if index == .count do
            return .add(values)
        Debug.assert(.count + sliceCount <= N, "the array is full")
        .count += sliceCount

        #static if Reflection.hasPostMove(T)
        {
            for var idx = .count - 1; idx >= index + sliceCount; idx -= 1 do
                .buffer[idx] = #relocate .buffer[idx - sliceCount]
        }
        else
        {
            Memory.copyOverlapping(&.buffer[index + sliceCount], &.buffer[index], #sizeof(T) * (.count - sliceCount - index))
        }

        #static if Reflection.hasPostCopy(T)
        {
            let vals = values!
            for var idx = 0; idx < sliceCount; idx += 1 do
                .buffer[index + idx] = #nodrop vals[idx]
        }
        else
        {
            Memory.copy(&.buffer[index], values.buffer, #sizeof(T) * sliceCount)
        }
    }

    // Moves elements from a slice at a specific index, shifting existing elements to the right.
    // Asserts if the array does not have enough capacity. Order is preserved.
    mtd emplaceAt(index: u64, values: [..] T)
        where Reflection.canCopy(T)
    {
        var sliceCount = values.count
        if !sliceCount do
            return
        let buffer = cast([*] T) &.buffer[0]
        let dataof = values.buffer
        if dataof >= buffer and dataof < buffer + .count
        {
            var copy: Array'T
            copy.add(values)
            return .emplaceAt(index, copy.toSlice())
        }

        Debug.assert(index <= .count, "index out of range")
        if index == .count do
            return .add(values)
        Debug.assert(.count + sliceCount <= N, "the array is full")
        .count += sliceCount

        #static if Reflection.hasPostMove(T)
        {
            for var idx = .count - 1; idx >= index + sliceCount; idx -= 1 do
                .buffer[idx] = #relocate .buffer[idx - sliceCount]
        }
        else
        {
            Memory.copyOverlapping(&.buffer[index + values.count], &.buffer[index], #sizeof(T) * (.count - sliceCount - index))
        }

        #static if Reflection.hasPostMove(T)
        {
            for var idx = 0; idx < sliceCount; idx += 1 do
                .buffer[index + idx] = #nodrop #move values[idx]
        }
        else
        {
            Memory.copy(&.buffer[index], values.buffer, #sizeof(T) * sliceCount)
        }
    }

    // Appends all elements from a slice to the end of the array.
    // Asserts if the array does not have enough capacity.
    mtd add(values: const [..] T?)
        where Reflection.canCopy(T)
    {
        var sliceCount = values.count
        if !sliceCount do
            return
        let buffer = cast([*] T) &.buffer[0]
        let dataof = values.buffer
        if dataof >= buffer and dataof < buffer + .count
        {
            var copy: Array'T
            copy.add(values)
            return .add(copy.toSlice())
        }

        Debug.assert(.count + sliceCount <= N, "the array is full")
        var oldCount = .count
        .count += sliceCount

        #static if Reflection.hasPostCopy(T)
        {
            let vals    = values!
            var destPtr = cast([*] T) &.buffer[oldCount]
            for index in sliceCount
            {
                destPtr[] = #nodrop vals[index]
                destPtr   += 1
            }
        }
        else
        {
            Memory.copy(&.buffer[oldCount], values.buffer, sliceCount * #sizeof(T))
        }
    }

    // Removes a specified number of elements starting from a given index.
    // This is an unstable remove; the order of remaining elements is not preserved.
    mtd remove(index, num: u64)
    {
        if !num do
            return
        Debug.assert(index + num <= .count, "index out of range")
        let oldCount   = .count
        let shiftCount = .count - (index + num)

        #static if !Reflection.hasPostMove(T) and !Reflection.hasDrop(T)
        {
            Memory.copyOverlapping(cast([*] T) &.buffer[0] + index, cast([*] T) &.buffer[0] + index + num, shiftCount * #sizeof(T))
        }
        else
        {
            // Drop the removed elements, then relocate the survivors into the freed slots.
            #static if Reflection.hasDrop(T)
            {
                Swag.drop(&.buffer[index], num)
            }

            for i in shiftCount
            {
                .buffer[index + i] = #relocate .buffer[index + num + i]
            }
        }

        .count -= num

        #static if Reflection.hasDrop(T) or Reflection.hasPostCopy(T) or Reflection.hasPostMove(T)
        {
            Swag.init(&.buffer[.count], oldCount - .count)
        }
    }

    // Removes the first occurrence of a given value from the array.
    // This is an unstable remove; order is not preserved. Does nothing if the value is not found.
    mtd(V) remove(value: V)
    {
        let idx = Slice.findLinear(.toSlice(), value)
        if idx == Swag.U64.Max do
            return
        .removeAt(idx)
    }

    // Removes the element at a given index by swapping it with the last element.
    // This is very fast, but the order of elements is not preserved.
    mtd removeAt(index: u64)
    {
        Debug.assert(index < .count, "index out of range")
        let oldCount = .count
        .count -= 1
        if index == .count
        {
            Swag.drop(&.buffer[.count])
        }
        else
        {
            Swag.drop(&.buffer[index])
            .buffer[index] = #relocate .buffer[.count]
        }

        #static if Reflection.hasDrop(T) or Reflection.hasPostCopy(T) or Reflection.hasPostMove(T)
        {
            Swag.init(&.buffer[.count], oldCount - .count)
        }
    }

    // Removes one or more elements at a given index, shifting subsequent elements to the left.
    // This is slower than 'removeAt', but preserves the order of the remaining elements.
    mtd removeAtOrdered(index: u64, numValues: u64 = 1)
    {
        if !numValues do
            return
        Debug.assert(index + numValues <= .count, "index out of range")
        let oldCount = .count
        .count -= numValues

        #static if Reflection.hasDrop(T)
        {
            for idx in numValues do
                Swag.drop(&.buffer[index + idx])
        }

        if index >= .count
        {
            #static if Reflection.hasDrop(T) or Reflection.hasPostCopy(T) or Reflection.hasPostMove(T)
            {
                Swag.init(&.buffer[.count], oldCount - .count)
            }

            return
        }

        #static if Reflection.hasPostMove(T)
        {
            var idx = index
            for .count - index
            {
                .buffer[idx] = #relocate .buffer[idx + numValues]
                idx          += 1
            }
        }
        else
        {
            Memory.copyOverlapping(&.buffer[index], &.buffer[index + numValues], #sizeof(T) * (.count - index))
        }

        #static if Reflection.hasDrop(T) or Reflection.hasPostCopy(T) or Reflection.hasPostMove(T)
        {
            Swag.init(&.buffer[.count], oldCount - .count)
        }
    }

    // Removes the first occurrence of a given value, preserving the order of remaining elements.
    // Does nothing if the value is not found.
    mtd(V) removeOrdered(value: V)
    {
        let idx = Slice.findLinear(.toSlice(), value)
        if idx == Swag.U64.Max do
            return
        .removeAtOrdered(idx)
    }

    // Returns 'true' if the array contains the given value.
    mtd(V) contains(value: V)->bool
    {
        return Slice.findLinear(.toSlice(), value) != Swag.U64.Max
    }

    // Sorts the array in ascending order using the default comparison operator.
    mtd sort()
        where Reflection.canCompare(T)
    {
        Slice.sort(.toSlice(), func(x, y: T)->s32 => x <=> y)
    }

    // Sorts the array in descending order.
    mtd sortReverse()
        where Reflection.canCompare(T)
    {
        Slice.sort(.toSlice(), func(x, y: T)->s32 => y <=> x)
    }

    // Sorts the array using a custom comparison function.
    mtd sort(cb: func||(T, T)->s32)
    {
        Debug.assert(cb != null)
        Slice.sort(.toSlice(), cb)
    }

    // Returns a copy of the first element of the array.
    // Asserts if the array is empty.
    mtd front()->T
    {
        Debug.assert(.count > 0, "array is empty")
        let result: retval = .buffer[0]
        return result
    }

    // Returns a pointer to the first element of the array.
    // Asserts if the array is empty.
    mtd frontPtr()->*T
    {
        Debug.assert(.count > 0, "array is empty")
        return &.buffer[0]
    }

    // Returns a copy of the last element of the array.
    // Asserts if the array is empty.
    mtd back()->T
    {
        Debug.assert(.count > 0, "array is empty")
        let result: retval = .buffer[.count - 1]
        return result
    }

    // Returns a pointer to the last element of the array.
    // Asserts if the array is empty.
    mtd backPtr()->*T
    {
        Debug.assert(.count > 0, "array is empty")
        return &.buffer[.count - 1]
    }

    // Removes the last element from the array and returns it.
    // Asserts if the array is empty.
    mtd popBack()->T
    {
        Debug.assert(.count > 0, "array is empty")
        var result: retval
        let backIndex = .count - 1
        result = #relocate .buffer[backIndex]
        #static if Reflection.hasDrop(T) or Reflection.hasPostCopy(T) or Reflection.hasPostMove(T)
        {
            Swag.init(&.buffer[backIndex], 1)
        }

        .count -= 1
        return result
    }

    // Removes the last element from the array.
    // Asserts if the array is empty.
    mtd removeBack()
    {
        Debug.assert(.count > 0, "array is empty")
        let backIndex = .count - 1
        Swag.drop(&.buffer[backIndex])
        #static if Reflection.hasDrop(T) or Reflection.hasPostCopy(T) or Reflection.hasPostMove(T)
        {
            Swag.init(&.buffer[backIndex], 1)
        }

        .count -= 1
    }
}
