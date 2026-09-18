#global public
#global namespace Reflection

using Swag

// Returns whether `t` is an instance of [[Core.Array]].
func isDynamicArray(t: typeinfo?)->bool
{
    if not t or not isStruct(t) do
        return false

    let tt = cast #assume(const *TypeInfoStruct) t
    let arrayGeneric = (cast #assume(const *TypeInfoStruct) #typeof(Array'u8)).fromGeneric
    if not tt.fromGeneric do
        return false
    return tt.fromGeneric.fullname == arrayGeneric.fullname
}

// Returns the element type of a [[Core.Array]] type, or null when `t` is not one.
func dynamicArrayElementType(t: typeinfo?)->typeinfo?
{
    if not isDynamicArray(t) do
        return null

    let tt       = cast #assume(const *TypeInfoStruct) t!
    let generics = tt.generics!
    return generics[0].pointedType
}

// Drops every element of the [[Core.Array]] at `arrayPointer`, whose element type is `elementType`.
//
// The array keeps its capacity. Nothing happens when a pointer or `elementType` is null.
func clearDynamicArray(arrayPointer: *void?, elementType: typeinfo?)
{
    if not arrayPointer or not elementType do
        return

    let arr = cast(*Array'u8) arrayPointer
    if hasDrop(elementType)
    {
        var scan = arr.buffer
        for arr.count
        {
            Memory.dropType(scan, elementType)
            scan += elementType.sizeof
        }
    }

    arr.count = 0
}

// Removes the element at `index` from the [[Core.Array]] at `arrayPointer`, whose element type is `elementType`.
//
// The removed element is dropped, and the following elements move down one slot, running their
// post-move hook, so the order is preserved. `index` must be in range.
func removeDynamicArrayElement(arrayPointer: *void?, elementType: typeinfo?, index: u64)
{
    if not arrayPointer or not elementType do
        return

    let arr       = cast(*Array'u8) arrayPointer
    let sizeValue = elementType.sizeof

    if index >= arr.count
    {
        Swag.assert(false)
        return
    }

    let removed = arr.buffer + index * sizeValue
    Memory.dropType(removed, elementType)

    if index != arr.count - 1
    {
        let countMove = arr.count - index - 1
        if hasPostMove(elementType)
        {
            for i in index until arr.count - 1
            {
                Memory.copy(arr.buffer + i * sizeValue, arr.buffer + (i + 1) * sizeValue, sizeValue)
                Memory.postMoveType(arr.buffer + (i * sizeValue), elementType)
            }
        }
        else do
            Memory.copyOverlapping(removed, removed + sizeValue, countMove * sizeValue)
    }

    arr.count -= 1
    Memory.clear((arr.buffer + arr.count * sizeValue)!, sizeValue)
}

// Swaps the values at `indexA` and `indexB` in a contiguous buffer of `valueType` values.
//
// `basePointer` can address a static array or the `buffer` of a [[Core.Array]]. Values whose type
// has a post-move hook are fixed up after their bytes are relocated.
func swapRuntimeValues(basePointer: *void?, valueType: typeinfo?, indexA, indexB: u64)
{
    if not basePointer or not valueType or indexA == indexB do
        return

    let size = valueType.sizeof
    let base = cast([*] u8) basePointer
    let pa   = base + indexA * size
    let pb   = base + indexB * size

    let allocator = Swag.getContext().allocator
    let tmp       = cast([*] u8) Memory.alloc(size, allocator)
    defer Memory.free(tmp, size, allocator)

    Memory.copy(tmp, pa, size)
    Memory.copy(pa, pb, size)
    Memory.copy(pb, tmp, size)

    // Each element kept its own bytes but landed at a new address: fix up self-references.
    if hasPostMove(valueType)
    {
        Memory.postMoveType(pa, valueType)
        Memory.postMoveType(pb, valueType)
    }
}

// Appends a slot to the [[Core.Array]] at `arrayPointer`, whose element type is `elementType`, and returns its address.
//
// With `initialize` true, the new slot receives the element type's default value. With
// `initialize` false, the slot is only zeroed and the caller must fully initialize it, as
// deserialization does; this supports element types without an implicit default, such as
// non-null interfaces. Panics when a pointer is null or when a default value is requested
// for a type that has none.
func appendDynamicArrayElement(arrayPointer: *void?, elementType: typeinfo?, initialize: bool = true)->*void?
{
    if not arrayPointer or not elementType
    {
        Swag.panic("Reflection.appendDynamicArrayElement cannot append to a null array or null type", #curlocation)
        return null
    }

    if initialize and not Memory.canDefaultInit(elementType)
    {
        Swag.panic("Reflection.appendDynamicArrayElement cannot default-initialize this type", #curlocation)
        return null
    }

    // Views the array as a buffer of bytes to reach its fields without the element type.
    let arr       = cast(*Array'u8) arrayPointer
    let sizeValue = elementType.sizeof

    // Growing relocates every value, so values with a post-move hook are fixed up afterwards.
    if arr.count >= arr.capacity
    {
        if arr.allocator == null do
            arr.allocator = Swag.getContext().allocator

        let oldBuffer   = arr.buffer
        let oldCapacity = arr.capacity
        let newCapacity = Math.max(arr.count + 1, arr.capacity * 2)
        let newBuffer   = cast([*] u8) Memory.alloc(newCapacity * sizeValue, arr.allocator)
        Memory.clear(newBuffer, newCapacity * sizeValue)

        Memory.copy(newBuffer, oldBuffer, arr.count * sizeValue)
        if hasPostMove(elementType)
        {
            var buf = newBuffer
            for arr.count
            {
                Memory.postMoveType(buf, elementType)
                buf += sizeValue
            }
        }

        Memory.free(oldBuffer, oldCapacity * sizeValue, arr.allocator)
        arr.buffer   = newBuffer
        arr.capacity = newCapacity
    }

    let result = arr.buffer + (arr.count * sizeValue)
    arr.count += 1
    if initialize do
        Memory.defaultInit(result, elementType)
    else do
        Memory.clear(result!, sizeValue)

    return result
}
