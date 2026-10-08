#global public
#global namespace Reflection

using Swag

// Returns whether `t` is an instance of [[Core.Array]].
func isDynamicArray(t: typeinfo?)->bool
{
    if not t or not isStruct(t) do
        return false

    let typeStruct   = assume cast(const *TypeInfoStruct, t)
    let arrayGeneric = assume cast(const *TypeInfoStruct, #typeof(Array'u8)).fromGeneric
    if not typeStruct.fromGeneric do
        return false
    return typeStruct.fromGeneric.fullname == arrayGeneric.fullname
}

// Returns the element type of a [[Core.Array]] type, or null when `t` is not one.
func dynamicArrayElementType(t: typeinfo?)->typeinfo?
{
    if not isDynamicArray(t) do
        return null

    let typeStruct = assume cast(const *TypeInfoStruct, t)
    let generics   = typeStruct.generics!
    return generics[0].pointedType
}

// Drops every element of the [[Core.Array]] at `arrayPointer`, whose element type is `elementType`.
//
// The array keeps its capacity. Nothing happens when a pointer or `elementType` is null.
func clearDynamicArray(arrayPointer: *void?, elementType: typeinfo?)
{
    if not arrayPointer or not elementType do
        return

    let arrayView = cast(*Array'u8, arrayPointer)
    if hasDrop(elementType)
    {
        var scan = arrayView.buffer
        for arrayView.count
        {
            Memory.dropType(scan, elementType)
            scan += elementType.sizeof
        }
    }

    arrayView.count = 0
}

// Removes the element at `index` from the [[Core.Array]] at `arrayPointer`, whose element type is `elementType`.
//
// The removed element is dropped, and the following elements move down one slot, running their
// post-move hook, so the order is preserved. `index` must be in range.
func removeDynamicArrayElement(arrayPointer: *void?, elementType: typeinfo?, index: u64)
{
    if not arrayPointer or not elementType do
        return

    let arrayView    = cast(*Array'u8, arrayPointer)
    let elementBytes = elementType.sizeof

    if index >= arrayView.count
    {
        Swag.assert(false)
        return
    }

    let removed = arrayView.buffer + index * elementBytes
    Memory.dropType(removed, elementType)

    if index != arrayView.count - 1
    {
        let movedElements = arrayView.count - index - 1
        if hasPostMove(elementType)
        {
            for i in index until arrayView.count - 1
            {
                Memory.copy(arrayView.buffer + i * elementBytes,
                            arrayView.buffer + (i + 1) * elementBytes,
                            elementBytes)
                Memory.postMoveType(arrayView.buffer + (i * elementBytes), elementType)
            }
        }
        else
        {
            Memory.copyOverlapping(removed, removed + elementBytes, movedElements * elementBytes)
        }
    }

    arrayView.count -= 1
    Memory.clear((arrayView.buffer + arrayView.count * elementBytes)!, elementBytes)
}

// Swaps the values at `indexA` and `indexB` in a contiguous buffer of `valueType` values.
//
// `basePointer` can address a static array or the `buffer` of a [[Core.Array]]. Values whose type
// has a post-move hook are fixed up after their bytes are relocated.
func swapRuntimeValues(basePointer: *void?, valueType: typeinfo?, indexA, indexB: u64)
{
    if not basePointer or not valueType or indexA == indexB do
        return

    let valueBytes = valueType.sizeof
    let base       = cast([*] u8, basePointer)
    let leftValue  = base + indexA * valueBytes
    let rightValue = base + indexB * valueBytes

    let allocator = Swag.getContext().allocator
    let temporary = cast([*] u8, Memory.alloc(valueBytes, allocator))
    defer Memory.free(temporary, valueBytes, allocator)

    Memory.copy(temporary, leftValue, valueBytes)
    Memory.copy(leftValue, rightValue, valueBytes)
    Memory.copy(rightValue, temporary, valueBytes)

    // Each element kept its own bytes but landed at a new address: fix up self-references.
    if hasPostMove(valueType)
    {
        Memory.postMoveType(leftValue, valueType)
        Memory.postMoveType(rightValue, valueType)
    }
}

// Appends a slot to the [[Core.Array]] at `arrayPointer`, whose element type is `elementType`, and returns its address.
//
// With `initialize` true, the new slot receives the element type's default value. With
// `initialize` false, the slot is only zeroed and the caller must fully initialize it, as
// deserialization does; this supports element types without an implicit default, such as
// non-null interfaces. Panics when a pointer is null or when a default value is requested
// for a type that has none.
func appendDynamicArrayElement(arrayPointer: *void?, elementType: typeinfo?, initialize: bool = true)->*void
{
    if not arrayPointer or not elementType do
        Swag.panic("Reflection.appendDynamicArrayElement cannot append to a null array or null type", #curlocation)
    if initialize and not Memory.canDefaultInit(elementType) do
        Swag.panic("Reflection.appendDynamicArrayElement cannot default-initialize this type", #curlocation)

    // Views the array as a buffer of bytes to reach its fields without the element type.
    let arrayView    = cast(*Array'u8, arrayPointer)
    let elementBytes = elementType.sizeof

    // Growing relocates every value, so values with a post-move hook are fixed up afterwards.
    if arrayView.count >= arrayView.capacity
    {
        if arrayView.allocator == null do
            arrayView.allocator = Swag.getContext().allocator

        let oldBuffer   = arrayView.buffer
        let oldCapacity = arrayView.capacity
        let newCapacity = Math.max(arrayView.count + 1, arrayView.capacity * 2)
        let newBuffer   = cast([*] u8, Memory.alloc(newCapacity * elementBytes, arrayView.allocator))
        Memory.clear(newBuffer, newCapacity * elementBytes)

        Memory.copy(newBuffer, oldBuffer, arrayView.count * elementBytes)
        if hasPostMove(elementType)
        {
            var movedElement = newBuffer
            for arrayView.count
            {
                Memory.postMoveType(movedElement, elementType)
                movedElement += elementBytes
            }
        }

        Memory.free(oldBuffer, oldCapacity * elementBytes, arrayView.allocator)
        arrayView.buffer   = newBuffer
        arrayView.capacity = newCapacity
    }

    // The buffer holds at least one free slot here.
    let result = arrayView.buffer! + (arrayView.count * elementBytes)
    arrayView.count += 1
    if initialize do
        Memory.defaultInit(result, elementType)
    else do
        Memory.clear(result, elementBytes)

    return result
}
