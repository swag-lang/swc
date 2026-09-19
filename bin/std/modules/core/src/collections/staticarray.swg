#global export

using Swag

// An array of at most `N` elements stored inline, with a capacity fixed at compile time.
//
// It offers the interface of [[Core.Array]] without ever allocating. Adding past the capacity
// asserts.
struct(T, N: u64) StaticArray
{
    public
    {
        buffer: [N] T     // The inline storage that holds the elements.
        count:  u64       // The number of valid elements currently in the array.
    }
}

impl StaticArray
{
    // Returns the number of elements in the array.
    #[Inline]
    mtd const opCount()->u64 => .count

    // Returns a constant pointer to the first element.
    #[Inline]
    mtd opData()->const *T => &.buffer[0]

    // Converts the array to a mutable slice over its elements.
    #[Inline]
    mtd opCast()->[..] T => .toSlice()

    // Converts the array to an immutable slice over its elements.
    #[Inline]
    mtd const opCast()->const [..] T => .toSlice()

    // Returns a mutable slice over the elements from `lower` to `upper`, both included.
    #[Inline]
    mtd opSlice(lower, upper: u64)->[..] T
    {
        Debug.safetyBoundCheck(lower <= upper, "lower bound greater than upper bound")
        Debug.safetyBoundCheck(lower < .count, "lower bound out of range")
        Debug.safetyBoundCheck(upper < .count, "upper bound out of range")
        return Swag.makeSlice(&.buffer[lower], (upper + 1) - lower)
    }

    // Returns the address of the element at `index`.
    #[Inline]
    mtd const opIndexPtr(index: u64)->const *T
    {
        Debug.safetyBoundCheck(index < .count, "index out of range")
        return &.buffer[index]
    }

    // Returns the mutable address of the element at `index`.
    #[Inline]
    mtd opIndexPtr(index: u64)->*T
    {
        Debug.safetyBoundCheck(index < .count, "index out of range")
        return &.buffer[index]
    }

    // Assigns a copy of `value` to the element at `index`.
    #[Inline]
    mtd opIndexSet(index: u64, value: T)
        where Reflection.canCopy(T)
    {
        Debug.safetyBoundCheck(index < .count, "index out of range")
        .buffer[index] = value
    }

    // Applies a compound assignment such as `+=` or `-=` to the element at `index`.
    #[Inline]
    mtd(op: Swag.Operator) opIndexAssign(index: u64, value: T)
    {
        Debug.safetyBoundCheck(index < .count, "index out of range")
        #ast("buffer[index] ", op.symbol(), " value")
    }

    // Replaces the content of the array with copies of the elements of `arr`.
    //
    // `arr` can borrow from this array. Asserts if it holds more than `N` elements.
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
        if not countof do
            return
        Swag.assert(countof <= N, "slice is too big")
        var dataof = arr.buffer

        #static if Reflection.hasPostCopy(T) or Reflection.hasDynamicStorage(T)
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

    // Visits every element in order, binding `item` to the element and `index` to its position.
    //
    // Visiting by address binds `item` to a mutable pointer. Otherwise a struct element is bound
    // through a constant pointer and any other element by value.
    #[Macro]
    mtd(ptr: bool) opVisit(stmt: #code(item, index: u64))
    {
        if not .count do
            return

        // The cursor advances at the top of the loop, so a 'continue' in the visited code cannot skip it.
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
    mtd reversed()->ReversedSlice'T => reverseSlice(.toSlice())

    // Returns an immutable zero-allocation view that traverses the elements from last to first.
    mtd const reversed()->ConstReversedSlice'T => reverseSlice(.toSlice())

    // Returns a zero-allocation view over adjacent elements.
    mtd const pairs()->Pairs'T => pairsView(.toSlice())

    // Drops every element and leaves the array empty.
    //
    // The storage is inline, so this is the same as [[clear]].
    mtd free()
    {
        .clear()
    }

    // Returns whether the array contains no elements.
    #[Inline]
    mtd const isEmpty() => .count == 0

    // Returns a mutable slice over the elements.
    #[Inline]
    mtd toSlice()->[..] T => Swag.makeSlice(&.buffer[0], .count)

    // Returns an immutable slice over the elements.
    #[Inline]
    mtd const toSlice()->const [..] T => Swag.makeSlice(&.buffer[0], .count)

    // Sets the number of elements to `newCount`.
    //
    // New elements are default-initialized, and elements past `newCount` are dropped. Asserts if
    // `newCount` exceeds `N`.
    mtd resize(newCount: u64)
    {
        if newCount == .count do
            return
        Swag.assert(newCount <= N, "size is too big")
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

    // Drops every element and leaves the array empty.
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

    // Appends `value` unless the array already contains an equal element.
    //
    // Asserts if the array is full. The value is copied; pass it with `#move` to move it instead.
    mtd addOnce(value: #fwd T)
    {
        if .contains(value) do
            return
        Swag.assert(.count != N, "the array is full")
        .buffer[.count] = #nodrop #fwd value
        .count += 1
    }

    // Appends `value` to the end of the array.
    //
    // Asserts if the array is full. The value is copied; pass it with `#move` to move it instead.
    mtd add(value: #fwd T)
    {
        Swag.assert(.count != N, "the array is full")
        .buffer[.count] = #nodrop #fwd value
        .count += 1
    }

    // Appends `num` uninitialized elements and returns the address of the first one.
    //
    // The caller must initialize every new element before the array reads, copies, or drops it.
    // Asserts if the array does not have enough capacity.
    mtd emplaceAddress(num: u32 = 1)->[*] T
    {
        Swag.assert(.count + num <= N, "the array is full")
        .count += num
        return cast([*] T) &.buffer[0] + .count - num
    }

    // Appends `num` default-initialized elements and returns the address of the first one.
    //
    // Asserts if the array does not have enough capacity.
    mtd emplaceInitAddress(num: u32 = 1)->[*] T
    {
        Swag.assert(.count + num <= N, "the array is full")
        .count += num
        let res = cast([*] T) &.buffer[0] + .count - num
        Swag.init(res, num)
        return res
    }

    // Inserts `value` at `index`, shifting the following elements to the right.
    //
    // Asserts if the array is full. The value is copied; pass it with `#move` to move it instead.
    // `value` can be an element of this array.
    mtd insertAt(index: u64, value: #fwd T)
    {
        Swag.assert(index <= .count, "index out of range")
        if index == .count do
            return .add(#fwd value)
        Swag.assert(.count != N, "the array is full")

        // Shifting rewrites the storage `value` may live in, so take it out first.
        var staged: T = #fwd value
        .count += 1

        #static if Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
        {
            for var idx = .count - 1; idx > index; idx -= 1 do
                .buffer[idx] = #relocate .buffer[idx - 1]
        }
        else
        {
            Memory.copyOverlapping(&.buffer[index + 1], &.buffer[index], #sizeof(T) * (.count - 1 - index))
        }

        .buffer[index] = #relocate staged
    }

    // Inserts copies of the elements of `values` at `index`, shifting the following elements to the right.
    //
    // `values` can borrow from this array. Asserts if the array does not have enough capacity.
    mtd insertAt(index: u64, values: const [..] T?)
        where Reflection.canCopy(T)
    {
        var sliceCount = values.count
        if not sliceCount do
            return
        let buffer = cast([*] T) &.buffer[0]
        let dataof = values.buffer
        if dataof >= buffer and dataof < buffer + .count
        {
            var copy: Array'T
            copy.add(values)
            return .insertAt(index, copy.toSlice())
        }

        Swag.assert(index <= .count, "index out of range")
        Swag.assert(.count + sliceCount <= N, "the array is full")
        .count += sliceCount

        #static if Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
        {
            for var idx = .count - 1; idx >= index + sliceCount; idx -= 1 do
                .buffer[idx] = #relocate .buffer[idx - sliceCount]
        }
        else
        {
            Memory.copyOverlapping(&.buffer[index + sliceCount], &.buffer[index], #sizeof(T) * (.count - sliceCount - index))
        }

        #static if Reflection.hasPostCopy(T) or Reflection.hasDynamicStorage(T)
        {
            let vals = values!
            for var idx = 0; idx < sliceCount; idx += 1 do
                .buffer[index + idx] = #nodrop vals[idx]
        }
        else
        {
            Memory.copy(&.buffer[index], values.buffer, #sizeof(T) * sliceCount)

            // A bitwise move leaves the source holding the same resources: reset it so that its
            // own drop releases nothing.
            #static if Reflection.hasDrop(T) do
                Swag.init(values.buffer, sliceCount)
        }
    }

    // Moves the elements of `values` to `index`, shifting the following elements to the right.
    //
    // Asserts if the array does not have enough capacity.
    mtd emplaceAt(index: u64, values: [..] T)
        where Reflection.canCopy(T)
    {
        var sliceCount = values.count
        if not sliceCount do
            return
        let buffer = cast([*] T) &.buffer[0]
        let dataof = values.buffer
        if dataof >= buffer and dataof < buffer + .count
        {
            var copy: Array'T
            copy.add(values)
            return .emplaceAt(index, copy.toSlice())
        }

        Swag.assert(index <= .count, "index out of range")
        Swag.assert(.count + sliceCount <= N, "the array is full")
        .count += sliceCount

        #static if Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
        {
            for var idx = .count - 1; idx >= index + sliceCount; idx -= 1 do
                .buffer[idx] = #relocate .buffer[idx - sliceCount]
        }
        else
        {
            Memory.copyOverlapping(&.buffer[index + values.count], &.buffer[index], #sizeof(T) * (.count - sliceCount - index))
        }

        #static if Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
        {
            for var idx = 0; idx < sliceCount; idx += 1 do
                .buffer[index + idx] = #nodrop #move values[idx]
        }
        else
        {
            Memory.copy(&.buffer[index], values.buffer, #sizeof(T) * sliceCount)

            // A bitwise move leaves the source holding the same resources: reset it so that its
            // own drop releases nothing.
            #static if Reflection.hasDrop(T) do
                Swag.init(values.buffer, sliceCount)
        }
    }

    // Appends copies of the elements of `values` to the end of the array.
    //
    // `values` can be null or borrow from this array. Asserts if the array does not have enough capacity.
    mtd add(values: const [..] T?)
        where Reflection.canCopy(T)
    {
        var sliceCount = values.count
        if not sliceCount do
            return
        let buffer = cast([*] T) &.buffer[0]
        let dataof = values.buffer
        if dataof >= buffer and dataof < buffer + .count
        {
            var copy: Array'T
            copy.add(values)
            return .add(copy.toSlice())
        }

        Swag.assert(.count + sliceCount <= N, "the array is full")
        var oldCount = .count
        .count += sliceCount

        #static if Reflection.hasPostCopy(T) or Reflection.hasDynamicStorage(T)
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

    // Removes `num` elements starting at `index`, shifting the following elements to the left.
    //
    // The order of the remaining elements is preserved.
    mtd remove(index, num: u64)
    {
        if not num do
            return
        Swag.assert(index + num <= .count, "index out of range")
        let oldCount   = .count
        let shiftCount = .count - (index + num)

        #static if not (Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)) and not Reflection.hasDrop(T)
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

        #static if Reflection.hasDrop(T) or Reflection.hasPostCopy(T) or Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
        {
            Swag.init(&.buffer[.count], oldCount - .count)
        }
    }

    // Removes the first element equal to `value` by moving the last element into its place.
    //
    // The order of the remaining elements is not preserved. Does nothing when `value` is absent.
    mtd(V) remove(value: V)
    {
        let idx = Slice.findLinear(.toSlice(), value)
        if idx == Swag.U64.Max do
            return
        .removeAt(idx)
    }

    // Removes the element at `index` by moving the last element into its place.
    //
    // This takes constant time, but does not preserve the order of the remaining elements.
    mtd removeAt(index: u64)
    {
        Swag.assert(index < .count, "index out of range")
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

        #static if Reflection.hasDrop(T) or Reflection.hasPostCopy(T) or Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
        {
            Swag.init(&.buffer[.count], oldCount - .count)
        }
    }

    // Removes `numValues` elements starting at `index`, shifting the following elements to the left.
    //
    // This is slower than [[removeAt]], but preserves the order of the remaining elements.
    mtd removeAtOrdered(index: u64, numValues: u64 = 1)
    {
        if not numValues do
            return
        Swag.assert(index + numValues <= .count, "index out of range")
        let oldCount = .count
        .count -= numValues

        #static if Reflection.hasDrop(T)
        {
            for idx in numValues do
                Swag.drop(&.buffer[index + idx])
        }

        if index >= .count
        {
            #static if Reflection.hasDrop(T) or Reflection.hasPostCopy(T) or Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
            {
                Swag.init(&.buffer[.count], oldCount - .count)
            }

            return
        }

        #static if Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
        {
            var idx = index
            for .count - index
            {
                .buffer[idx] = #relocate .buffer[idx + numValues]
                idx += 1
            }
        }
        else
        {
            Memory.copyOverlapping(&.buffer[index], &.buffer[index + numValues], #sizeof(T) * (.count - index))
        }

        #static if Reflection.hasDrop(T) or Reflection.hasPostCopy(T) or Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
        {
            Swag.init(&.buffer[.count], oldCount - .count)
        }
    }

    // Removes the first element equal to `value`, preserving the order of the remaining elements.
    //
    // Does nothing when `value` is absent.
    mtd(V) removeOrdered(value: V)
    {
        let idx = Slice.findLinear(.toSlice(), value)
        if idx == Swag.U64.Max do
            return
        .removeAtOrdered(idx)
    }

    // Returns whether the array contains an element equal to `value`.
    mtd(V) const contains(value: V)->bool => Slice.findLinear(.toSlice(), value) != Swag.U64.Max

    // Sorts the elements in ascending order.
    //
    // The sort is not stable. See [[Core.Slice.sort]].
    mtd sort()
        where Reflection.canCompare(T)
    {
        Slice.sort(.toSlice())
    }

    // Sorts the elements in descending order.
    //
    // The sort is not stable.
    mtd sortReverse()
        where Reflection.canCompare(T)
    {
        Slice.sort(.toSlice(), descending: true)
    }

    // Sorts the elements in the order defined by `compare`.
    //
    // `compare` returns a negative value when its first argument must come first. The sort is not stable.
    mtd sort(compare: func||(T, T)->s32)
    {
        Slice.sort(.toSlice(), compare)
    }

    // Returns a copy of the first element.
    //
    // Asserts if the array is empty.
    mtd front()->T
    {
        Swag.assert(.count > 0, "array is empty")
        let result: retval = .buffer[0]
        return result
    }

    // Returns the address of the first element.
    //
    // Asserts if the array is empty.
    mtd frontPtr()->*T
    {
        Swag.assert(.count > 0, "array is empty")
        return &.buffer[0]
    }

    // Returns a copy of the last element.
    //
    // Asserts if the array is empty.
    mtd back()->T
    {
        Swag.assert(.count > 0, "array is empty")
        let result: retval = .buffer[.count - 1]
        return result
    }

    // Returns the address of the last element.
    //
    // Asserts if the array is empty.
    mtd backPtr()->*T
    {
        Swag.assert(.count > 0, "array is empty")
        return &.buffer[.count - 1]
    }

    // Removes the last element and returns it.
    //
    // Asserts if the array is empty.
    mtd popBack()->T
    {
        Swag.assert(.count > 0, "array is empty")
        var result: retval
        let backIndex = .count - 1
        result = #relocate .buffer[backIndex]
        #static if Reflection.hasDrop(T) or Reflection.hasPostCopy(T) or Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
        {
            Swag.init(&.buffer[backIndex], 1)
        }

        .count -= 1
        return result
    }

    // Drops and removes the last element.
    //
    // Asserts if the array is empty.
    mtd removeBack()
    {
        Swag.assert(.count > 0, "array is empty")
        let backIndex = .count - 1
        Swag.drop(&.buffer[backIndex])
        #static if Reflection.hasDrop(T) or Reflection.hasPostCopy(T) or Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
        {
            Swag.init(&.buffer[backIndex], 1)
        }

        .count -= 1
    }
}
