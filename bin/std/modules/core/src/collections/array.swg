#global export

using Swag

// A growable, contiguous array of elements of type `T`.
//
// The array owns its elements and its buffer, which grows as elements are added and is released
// when the array is dropped. Growth can move the elements and invalidates every pointer and slice
// borrowed from the array.
//
// An array is a header over a memory block, and that header is part of its contract: the
// serializers, the reflection helpers and the formatters build one over storage they already
// own. Writing 'count' is also how a caller truncates without dropping the elements, which
// 'clear' and 'resize' deliberately do not do. So these fields stay writable, unlike the state
// of a type that maintains an invariant across its fields.
struct(T) Array
{
    public
    {
        allocator: IAllocator?     // The allocator used for memory operations.
        buffer:    [*] T?          // Pointer to the contiguous memory block holding the elements.
        count:     u64             // The number of valid elements currently in the array.
        capacity:  u64             // The total number of elements that can be stored in the allocated buffer.
    }
}

impl Array
{
    // Returns the number of elements in the array.
    #[Inline]
    mtd const opCount()->u64 => .count

    // Returns a constant pointer to the first element, or null when no buffer is allocated.
    #[Inline]
    mtd opData()->const *T? => .buffer

    // Drops every element and releases the buffer.
    mtd opDrop()
    {
        .free()
    }

    #static if Reflection.canCopy(T)
    {
        // Gives a copied array its own buffer holding copies of the elements.
        //
        // An element that owns a release states no copy of its own, and nothing here can duplicate
        // what it owns: the array then states none either, and is handed over with '#move'.
        mtd opPostCopy()
        {
            if not .buffer do
                return

            let oldBuffer = .buffer
            .buffer = null
            .realloc(.count)
            if not .count do
                return

            #static if Reflection.hasPostCopy(T) or Reflection.hasDynamicStorage(T)
            {
                .initNewSlots(0, .count)
                let buffer = .buffer!
                for index in .count do
                    buffer[index] = #nodrop oldBuffer[index]
            }
            else
            {
                Memory.copy(.buffer, oldBuffer, #sizeof(T) * .count)
            }
        }
    }

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
        let buffer = .buffer!
        return Swag.makeSlice(buffer + lower, (upper + 1) - lower)
    }

    // Returns the address of the element at `index`.
    #[Inline]
    mtd const opIndexPtr(index: u64)->const *T
    {
        Debug.safetyBoundCheck(index < .count, "index out of range")
        let buffer = .buffer!
        return buffer + index
    }

    // Returns the mutable address of the element at `index`.
    #[Inline]
    mtd opIndexPtr(index: u64)->*T
    {
        Debug.safetyBoundCheck(index < .count, "index out of range")
        let buffer = .buffer!
        return buffer + index
    }

    // Assigns a copy of `value` to the element at `index`.
    #[Inline]
    mtd opIndexSet(index: u64, value: T)
        where Reflection.canCopy(T)
    {
        Debug.safetyBoundCheck(index < .count, "index out of range")
        let buffer = .buffer!
        buffer[index] = value
    }

    // Applies a compound assignment such as `+=` or `-=` to the element at `index`.
    #[Inline]
    mtd(op: Swag.Operator) opIndexAssign(index: u64, value: T)
    {
        Debug.safetyBoundCheck(index < .count, "index out of range")
        let buffer = .buffer!
        #ast("buffer[index] ", op.symbol(), " value")
    }

    // Replaces the content of the array with copies of the elements of `arr`.
    //
    // `arr` can borrow from this array.
    mtd opSet(arr: const [..] T)
        where Reflection.canCopy(T)
    {
        let countof = arr.count
        if countof and .buffer
        {
            let dataof = arr.buffer
            if dataof >= .buffer and dataof < .buffer + .count
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
        var dataof = arr.buffer

        .grow(countof)
        #static if Reflection.hasPostCopy(T) or Reflection.hasDynamicStorage(T)
        {
            .initNewSlots(0, countof)
            let buffer = .buffer!
            let srcPtr = dataof!
            for i in countof do
                buffer[i] = #nodrop srcPtr[i]
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
    func(ptr: bool) opVisit(const me, stmt: #code(item, index: u64))
    {
        if not .count do
            return
        let buffer = .buffer!

        // The cursor advances at the top of the loop, so a 'continue' in the visited code cannot skip it.
        var scan = buffer - 1

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

    // Returns the mutable address of the element at `x`.
    #[Inline]
    mtd ptr1(x: u64)->*T
    {
        Debug.safetyBoundCheck(x < .count, "index out of range")
        let buffer = .buffer!
        return buffer + x
    }

    // Returns the mutable address of the element at column `x` and row `y` of a grid `w` elements wide.
    //
    // The array is read as a row-major grid, so the element index is `x + y * w`.
    #[Inline]
    mtd ptr2(x, y, w: u64)->*T
    {
        Debug.safetyBoundCheck(x + y * w < .count, "index out of range")
        let buffer = .buffer!
        return buffer + x + y * w
    }

    // Reallocates the buffer to `newCapacity` elements, relocating the existing ones.
    #[Swag.NoDoc]
    mtd realloc(newCapacity: u64)
    {
        if not .allocator do
            .allocator = Swag.getContext().allocator

        if newCapacity == 0
        {
            Memory.free(.buffer, .capacity * #sizeof(T), .allocator)
            .buffer   = null
            .capacity = 0
            return
        }

        let newBuffer = cast([*] T) Memory.realloc(.buffer, newCapacity * #sizeof(T), .capacity * #sizeof(T), .allocator)

        // Elements that moved to a new block must be told so through 'opPostMove'.
        #static if Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
        {
            if .buffer and newBuffer != .buffer
            {
                Swag.postMove(newBuffer, .count)
            }
        }

        .buffer   = newBuffer
        .capacity = newCapacity
    }

    // Drops every element, releases the buffer, and leaves the array empty.
    mtd free()
    {
        if not .buffer do
            return

        // Drop every element before its storage goes away.
        #static if Reflection.hasDrop(T)
        {
            Swag.drop(.buffer, .count)
        }

        Memory.free(.buffer, .capacity * #sizeof(T), .allocator)
        .buffer = null
        .count, .capacity = 0
    }

    // Creates a byte array holding `size` zero bytes.
    func createBuffer(size: u64)->Array'u8
    {
        var result: retval
        result.resize(size)
        return result
    }

    // Returns whether the array contains no elements.
    #[Inline]
    mtd const isEmpty() => .count == 0

    // Returns a mutable slice containing all elements of the array.
    mtd toSlice()->[..] T => Swag.makeSlice(.buffer, .count)

    // Returns an immutable slice containing all elements of the array.
    mtd const toSlice()->const [..] T => Swag.makeSlice(.buffer, .count)

    // Returns the contiguous storage as a pointer the caller walks itself.
    //
    // An empty array owns no block, and a caller asking an empty array for its storage is
    // about to walk zero elements. The answer is then a dangling address, aligned for the
    // element type and never read, rather than a null every caller would have to assert:
    // walking is bounded by 'count', and a read through the dangling address faults exactly
    // as loudly as a read through null. Ask 'isEmpty' whether there is anything to walk, and
    // 'toSlice' when the walk should carry its own bounds.
    //
    // The pointer is mutable whatever the receiver, exactly like reading the field was: a
    // container that hands out its storage hands out the storage itself.
    #[Inline]
    mtd const storage()->[*] T => .buffer orelse cast([*] T) cast(u64) #alignof(T)

    #[Inline]
    #[Swag.NoDoc]
    mtd initNewSlots(index, num: u64)
    {
        if not num do
            return

        #static if Reflection.hasDrop(T) or Reflection.hasPostCopy(T) or Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
        {
            Swag.init(.buffer + index, num)
        }
    }

    // Ensures the capacity can hold at least `newCount` elements, at least doubling it when it grows.
    //
    // The element count is unchanged. See also [[reserve]].
    #[Swag.NoDoc]
    mtd grow(newCount: u64)
    {
        if newCount <= .capacity do
            return
        let newCapacity = Math.max(.capacity * 2, newCount)
        .reserve(newCapacity)
    }

    // Sets the capacity to at least `newCapacity`, keeping the elements already stored.
    //
    // Asking for a capacity of zero is the one exception: it releases the buffer and empties the
    // array, which is what 'free' does.
    mtd reserve(newCapacity: u64)
    {
        if not newCapacity
        {
            .free()
            .buffer = null
            .count, .capacity = 0
            return
        }

        if newCapacity <= .capacity do
            return

        .realloc(newCapacity)
    }

    // Grows the array to at least `newCount` elements, default-initializing the new ones.
    //
    // An array that already holds `newCount` elements or more is unchanged.
    mtd growResize(newCount: u64)
    {
        if newCount <= .count do
            return
        .grow(newCount)
        .resize(newCount)
    }

    // Sets the number of elements to `newCount`.
    //
    // New elements are default-initialized, and elements past `newCount` are dropped.
    mtd resize(newCount: u64)
    {
        if newCount == .count do
            return
        if newCount > .count
        {
            .grow(newCount)
            Swag.init(.buffer + .count, newCount - .count)
            .count = newCount
        }
        else
        {
            Swag.drop(.buffer + newCount, .count - newCount)
            .count = newCount
        }
    }

    // Drops every element and leaves the array empty, keeping its buffer for reuse.
    mtd clear()
    {
        #static if Reflection.hasDrop(T)
        {
            for index in .count do
                Swag.drop(.buffer + index)
        }

        .count = 0
    }

    // Assigns a copy of `value` to every element.
    mtd fill(value: T)
    {
        if not .count do
            return
        let buffer = .buffer!
        for i in .count do
            buffer[i] = value
    }

    // Appends `value` unless the array already contains an equal element.
    //
    // The containment check is a linear search. The value is copied; pass it with `#move` to move
    // it instead.
    mtd addOnce(value: #fwd T)
    {
        if .contains(value) do
            return
        .add(#fwd value)
    }

    // Appends `value` to the end of the array.
    //
    // The value is copied; pass it with `#move` to move it instead. `value` can be an element of
    // this array.
    mtd add(value: #fwd T)
    {
        // Growing releases the storage `value` may live in, so take it out first.
        if .count == .capacity
        {
            var staged: T = #fwd value
            .grow(.count + 1)
            .initNewSlots(.count, 1)
            .buffer![.count] = #relocate staged
            .count += 1
            return
        }

        .initNewSlots(.count, 1)
        let buffer = .buffer!
        buffer[.count] = #nodrop #fwd value
        .count         += 1
    }

    // Appends `num` uninitialized elements and returns the address of the first one.
    //
    // The caller must initialize every new element before the array reads, copies, or drops it.
    mtd emplaceAddress(num: u32 = 1)->[*] T
    {
        .grow(.count + num)
        .count += num
        let buffer = .buffer!
        return buffer + .count - num
    }

    // Appends `num` default-initialized elements and returns the address of the first one.
    mtd emplaceInitAddress(num: u32 = 1)->[*] T
    {
        .grow(.count + num)
        .count += num
        let buffer = .buffer!
        let res    = buffer + .count - num
        Swag.init(res, num)
        return res
    }

    // Inserts `value` at `index`, shifting the following elements to the right.
    //
    // The value is copied; pass it with `#move` to move it instead. `value` can be an element of
    // this array.
    mtd insertAt(index: u64, value: #fwd T)
    {
        Debug.safetyBoundCheck(index <= .count, "index out of range")
        if index == .count do
            return .add(#fwd value)

        // Growing and shifting both rewrite the storage `value` may live in, so take it out first.
        var staged: T = #fwd value
        .grow(.count + 1)
        .count += 1
        .initNewSlots(.count - 1, 1)
        let buffer = .buffer!

        #static if Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
        {
            for var idx = .count - 1; idx > index; idx -= 1 do
                buffer[idx] = #relocate buffer[idx - 1]
        }
        else
        {
            Memory.copyOverlapping(buffer + index + 1, buffer + index, #sizeof(T) * (.count - 1 - index))
        }

        buffer[index] = #relocate staged
    }

    // Inserts copies of the elements of `values` at `index`, shifting the following elements to the right.
    //
    // `values` can borrow from this array.
    mtd insertAt(index: u64, values: const [..] T)
        where Reflection.canCopy(T)
    {
        var sliceCount = values.count
        if not sliceCount do
            return
        if .buffer
        {
            let dataof = values.buffer
            if dataof >= .buffer and dataof < .buffer + .count
            {
                var copy: Array'T
                copy.add(values)
                return .insertAt(index, copy.toSlice())
            }
        }

        Debug.safetyBoundCheck(index <= .count, "index out of range")
        .grow(.count + sliceCount)
        .count += sliceCount
        .initNewSlots(.count - sliceCount, sliceCount)
        let buffer = .buffer!

        #static if Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
        {
            for var idx = .count - 1; idx >= index + sliceCount; idx -= 1 do
                buffer[idx] = #relocate buffer[idx - sliceCount]
        }
        else
        {
            Memory.copyOverlapping(buffer + index + sliceCount, buffer + index, #sizeof(T) * (.count - sliceCount - index))
        }

        #static if Reflection.hasPostCopy(T) or Reflection.hasDynamicStorage(T)
        {
            for var idx = 0; idx < sliceCount; idx += 1 do
                buffer[index + idx] = #nodrop values[idx]
        }
        else
        {
            Memory.copy(buffer + index, values.buffer, #sizeof(T) * sliceCount)
        }
    }

    // Moves the elements of `values` to `index`, shifting the following elements to the right.
    mtd emplaceAt(index: u64, values: [..] T)
        where Reflection.canCopy(T)
    {
        var sliceCount = values.count
        if not sliceCount do
            return
        if .buffer
        {
            let dataof = values.buffer
            if dataof >= .buffer and dataof < .buffer + .count
            {
                var copy: Array'T
                copy.add(values)
                return .emplaceAt(index, copy.toSlice())
            }
        }

        Debug.safetyBoundCheck(index <= .count, "index out of range")
        .grow(.count + sliceCount)
        .count += sliceCount
        .initNewSlots(.count - sliceCount, sliceCount)
        let buffer = .buffer!

        #static if Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
        {
            for var idx = .count - 1; idx >= index + sliceCount; idx -= 1 do
                buffer[idx] = #relocate buffer[idx - sliceCount]
        }
        else
        {
            Memory.copyOverlapping(buffer + index + values.count, buffer + index, #sizeof(T) * (.count - sliceCount - index))
        }

        #static if Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
        {
            for var idx = 0; idx < sliceCount; idx += 1 do
                buffer[index + idx] = #nodrop #move values[idx]
        }
        else
        {
            Memory.copy(buffer + index, values.buffer, #sizeof(T) * sliceCount)
        // A bitwise move leaves the source holding the same resources: reset it so that its
        // own drop releases nothing.
        #static if Reflection.hasDrop(T) do
            Swag.init(values.buffer, sliceCount)
        }
    }

    // Appends copies of the elements of `values` to the end of the array.
    //
    // `values` can be null or borrow from this array.
    mtd add(values: const [..] T?)
        where Reflection.canCopy(T)
    {
        var sliceCount = values.count
        if not sliceCount do
            return
        if .buffer
        {
            let dataof = values.buffer
            if dataof >= .buffer and dataof < .buffer + .count
            {
                var copy: Array'T
                copy.add(values)
                return .add(copy.toSlice())
            }
        }

        .grow(.count + sliceCount)
        var oldCount = .count
        .count += sliceCount
        .initNewSlots(oldCount, sliceCount)
        let buffer = .buffer!

        #static if Reflection.hasPostCopy(T) or Reflection.hasDynamicStorage(T)
        {
            let vals    = values!
            var destPtr = buffer + oldCount
            for index in sliceCount
            {
                destPtr[] = #nodrop vals[index]
                destPtr   += 1
            }
        }
        else
        {
            Memory.copy(buffer + oldCount, values.buffer, sliceCount * #sizeof(T))
        }
    }

    // Swaps the elements at `idx0` and `idx1`.
    mtd swap(idx0, idx1: u64)
    {
        if idx0 == idx1 do
            return
        Debug.safetyBoundCheck(idx0 < .count, "index out of range")
        Debug.safetyBoundCheck(idx1 < .count, "index out of range")
        swap((.buffer + idx0)!, (.buffer + idx1)!)
    }

    // Removes `num` elements starting at `index`, shifting the following elements to the left.
    //
    // The order of the remaining elements is preserved.
    mtd remove(index, num: u64)
    {
        if not num do
            return
        Debug.safetyBoundCheck(index + num <= .count, "index out of range")
        let shiftCount = .count - (index + num)

        #static if not (Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)) and not Reflection.hasDrop(T)
        {
            Memory.copyOverlapping(.buffer + index, .buffer + index + num, shiftCount * #sizeof(T))
        }
        else
        {
            // Drop the removed elements, then relocate the survivors into the freed slots.
            #static if Reflection.hasDrop(T)
            {
                Swag.drop(.buffer + index, num)
            }

            let buffer = .buffer!
            for i in shiftCount
            {
                buffer[index + i] = #relocate buffer[index + num + i]
            }
        }

        .count -= num
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
        Debug.safetyBoundCheck(index < .count, "index out of range")
        .count -= 1
        if index == .count
        {
            Swag.drop(.buffer + .count)
        }
        else
        {
            Swag.drop(.buffer + index)
            let buffer = .buffer!
            buffer[index] = #relocate buffer[.count]
        }
    }

    // Removes `numValues` elements starting at `index`, shifting the following elements to the left.
    //
    // This is slower than [[removeAt]], but preserves the order of the remaining elements.
    mtd removeAtOrdered(index: u64, numValues: u64 = 1)
    {
        if not numValues do
            return
        Debug.safetyBoundCheck(index + numValues <= .count, "index out of range")
        .count -= numValues

        #static if Reflection.hasDrop(T)
        {
            for idx in numValues do
                Swag.drop(.buffer + index + idx)
        }

        if index >= .count do
            return

        #static if Reflection.hasPostMove(T) or Reflection.hasDynamicStorage(T)
        {
            let buffer = .buffer!
            var idx    = index
            for .count - index
            {
                buffer[idx] = #relocate buffer[idx + numValues]
                idx         += 1
            }
        }
        else
        {
            Memory.copyOverlapping(.buffer + index, .buffer + index + numValues, #sizeof(T) * (.count - index))
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
    mtd const front()->T
    {
        Swag.assert(.count > 0, "array is empty")
        let buffer         = .buffer!
        let result: retval = buffer[0]
        return result
    }

    // Returns the address of the first element.
    //
    // Asserts if the array is empty.
    mtd frontPtr()->*T
    {
        Swag.assert(.count > 0, "array is empty")
        return .buffer!
    }

    // Returns a copy of the last element.
    //
    // Asserts if the array is empty.
    mtd const back()->T
    {
        Swag.assert(.count > 0, "array is empty")
        let buffer         = .buffer!
        let result: retval = buffer[.count - 1]
        return result
    }

    // Returns the address of the last element.
    //
    // Asserts if the array is empty.
    mtd backPtr()->*T
    {
        Swag.assert(.count > 0, "array is empty")
        let buffer = .buffer!
        return buffer + .count - 1
    }

    // Removes the last element and returns it.
    //
    // Asserts if the array is empty.
    mtd popBack()->T
    {
        Swag.assert(.count > 0, "array is empty")
        let buffer = .buffer!
        var result: retval
        result = #relocate buffer[.count - 1]
        .count -= 1
        return result
    }

    // Drops and removes the last element.
    //
    // Asserts if the array is empty.
    mtd removeBack()
    {
        Swag.assert(.count > 0, "array is empty")
        Swag.drop(.buffer + .count - 1)
        .count -= 1
    }
}

impl StrConv.IConvert for Array
{
    mtd const impl convert(buf: *ConcatBuffer, convFmt: StrConv.ConvertFormat, strFormat: string?)
    {
        buf.addBytes("[")
        if .count
        {
            let buffer = .buffer!
            for i in .count
            {
                if i do
                    buf.addBytes(", ")
                StrConv.convert'T(buf, buffer[i], convFmt, strFormat)
            }
        }

        buf.addBytes("]")
    }
}
