#global public
#global namespace Reflection

using Swag

// Returns whether the type is a Core dynamic array.
func isDynamicArray(t: #null typeinfo)->bool
{
    if !t or !isStruct(t) do
        return false

    let tt           = cast(const *TypeInfoStruct) t
    let arrayGeneric = (cast(const *TypeInfoStruct) #typeof(Array'u8)).fromGeneric
    if !tt.fromGeneric or !arrayGeneric do
        return false
    return tt.fromGeneric.fullname == arrayGeneric.fullname
}

// Returns a dynamic array's element type, or null for another kind of type.
func dynamicArrayElementType(t: #null typeinfo)->#null typeinfo
{
    if !isDynamicArray(t) do
        return null

    let tt       = cast(const *TypeInfoStruct) t!
    let generics = tt.generics!
    return generics[0].pointedType
}

// Removes every element from a runtime-typed dynamic array.
func clearDynamicArray(arrayPointer: #null *void, elementType: #null typeinfo)
{
    if !arrayPointer or !elementType do
        return

    let arr    = cast(*Array'u8) arrayPointer
    let nnType = elementType

    if hasDrop(nnType)
    {
        var scan = arr.buffer
        for arr.count
        {
            Memory.dropType(scan, nnType)
            scan += nnType.sizeof
        }
    }

    arr.count = 0
}

// Removes an element from a runtime-typed dynamic array while preserving value lifecycles.
func removeDynamicArrayElement(arrayPointer: #null *void, elementType: #null typeinfo, index: u64)
{
    if !arrayPointer or !elementType do
        return

    let arr       = cast(*Array'u8) arrayPointer
    let nnType    = elementType
    let sizeValue = nnType.sizeof

    if index >= arr.count
    {
        Debug.assert(false)
        return
    }

    let removed = arr.buffer + index * sizeValue
    Memory.dropType(removed, nnType)

    if index != arr.count - 1
    {
        let countMove = arr.count - index - 1
        if hasPostMove(nnType)
        {
            for i in index until arr.count - 1
            {
                Memory.copy(arr.buffer + i * sizeValue, arr.buffer + (i + 1) * sizeValue, sizeValue)
                Memory.postMoveType(arr.buffer + (i * sizeValue), nnType)
            }
        }
        else do
            Memory.copyOverlapping(removed, removed + sizeValue, countMove * sizeValue)
    }

    arr.count -= 1
    Memory.clear((arr.buffer + arr.count * sizeValue)!, sizeValue)
}

// Swap two elements (by index) inside a contiguous buffer of 'valueType'. Works for both a
// static array buffer and a 'Core.Array' buffer (pass arr.buffer), handling structs that need
// a post-move fixup after their bytes are relocated.
func swapRuntimeValues(basePointer: #null *void, valueType: #null typeinfo, indexA, indexB: u64)
{
    if !basePointer or !valueType or indexA == indexB do
        return

    let nnType = valueType
    let size   = nnType.sizeof
    let base   = cast([*] u8) basePointer
    let pa     = base + indexA * size
    let pb     = base + indexB * size

    let allocator = @getcontext().allocator
    let tmp       = cast([*] u8) Memory.alloc(size, allocator)
    defer Memory.free(tmp, size, allocator)

    Memory.copy(tmp, pa, size)
    Memory.copy(pa, pb, size)
    Memory.copy(pb, tmp, size)

    // Each element kept its own bytes but landed at a new address: fix up self-references.
    if hasPostMove(nnType)
    {
        Memory.postMoveType(pa, nnType)
        Memory.postMoveType(pb, nnType)
    }
}

// Add an element in a 'Core.Array' without knowing the type of the element at compile time but knowing it at runtime (valueType).
// With 'defaultInitSlot' false, the new slot is only zeroed and the CALLER must fully
// initialize it (deserialization does): this supports element types that have no
// implicit default, like non-null interfaces.
func appendDynamicArrayElement(arrayPointer: #null *void, elementType: #null typeinfo, initialize: bool = true)->#null *void
{
    if !arrayPointer or !elementType
    {
        @panic("Reflection.appendDynamicArrayElement cannot append to a null array or null type", #curlocation)
        return null
    }

    let nnType = elementType
    if initialize and !Memory.canDefaultInit(nnType)
    {
        @panic("Reflection.appendDynamicArrayElement cannot default-initialize this type", #curlocation)
        return null
    }

    // We will treat the array as a buffer of bytes, just to be able to access the fields
    let arr       = cast(*Array'u8) arrayPointer
    let sizeValue = nnType.sizeof

    // If we need to reallocate the buffer, we will also have to deal with
    // structures specials functions
    if arr.count >= arr.capacity
    {
        if arr.allocator == null do
            arr.allocator = @getcontext().allocator

        let oldBuffer   = arr.buffer
        let oldCapacity = arr.capacity
        let newCapacity = Math.max(arr.count + 1, arr.capacity * 2)
        let newBuffer   = cast([*] u8) Memory.alloc(newCapacity * sizeValue, arr.allocator)
        Memory.clear(newBuffer, newCapacity * sizeValue)

        // Move old values to the new buffer
        Memory.copy(newBuffer, oldBuffer, arr.count * sizeValue)
        if hasPostMove(nnType)
        {
            var buf = newBuffer
            for arr.count
            {
                Memory.postMoveType(buf, nnType)
                buf += sizeValue
            }
        }

        Memory.free(oldBuffer, oldCapacity * sizeValue, arr.allocator)
        arr.buffer   = newBuffer
        arr.capacity = newCapacity
    }

    let result = arr.buffer + (arr.count * nnType.sizeof)
    arr.count += 1
    if initialize do
        Memory.defaultInit(result, nnType)
    else do
        Memory.clear(result!, nnType.sizeof)

    return result
}
