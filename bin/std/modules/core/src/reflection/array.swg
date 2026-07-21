#global public
#global namespace Reflection
using Swag

// Returns true if the type 't' is a 'Core.Array' type
func isStructArray(t: #null typeinfo)->bool
{
    if !t or !isStruct(t) do
        return false

    let tt           = cast(const *TypeInfoStruct) t
    let arrayGeneric = (cast(const *TypeInfoStruct) #typeof(Array'u8)).fromGeneric
    if !tt.fromGeneric or !arrayGeneric do
        return false
    return tt.fromGeneric.fullname == arrayGeneric.fullname
}

// Returns the generic type of the 'Core.Array' typeinfo.
// If 't' is not a 'Core.Array', returns null
func getStructArrayType(t: #null typeinfo)->#null typeinfo
{
    if !isStructArray(t) do
        return null

    let tt = cast(const *TypeInfoStruct) notnull t
    return tt.generics[0].pointedType
}

// Used to clear a 'Core.Array' without knowing the type of the element at compile time but knowing it at runtime (valueType)
func clearStructArray(arrayPtr: #null *void, valueType: #null typeinfo)
{
    if !arrayPtr or !valueType do
        return

    let arr    = cast(*Array'u8) arrayPtr
    let nnType = valueType

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

// Remove an element in a 'Core.Array' without knowing the type of the element at compile time but knowing it at runtime (valueType)
func removeValueStructArray(arrayPtr: #null *void, valueType: #null typeinfo, index: u64)
{
    if !arrayPtr or !valueType do
        return

    // We will treat the array as a buffer of bytes, just to be able to access the fields
    let arr       = cast(*Array'u8) arrayPtr
    let nnType    = valueType
    let sizeValue = nnType.sizeof

    Debug.assert(index < arr.count)

    // Move all elements at the remove position
    if index != arr.count - 1
    {
        let countMove = arr.count - index - 1
        Memory.copy(arr.buffer + (index * sizeValue), arr.buffer + (index + 1) * sizeValue, countMove * sizeValue)
        if Reflection.hasPostMove(nnType)
        {
            for i in index until arr.count - 1 do
                Memory.postMoveType(arr.buffer + (i * sizeValue), nnType)
        }
    }

    // Drop the last element
    Memory.dropType(arr.buffer + (arr.count - 1) * sizeValue, nnType)

    arr.count -= 1
}

// Swap two elements (by index) inside a contiguous buffer of 'valueType'. Works for both a
// static array buffer and a 'Core.Array' buffer (pass arr.buffer), handling structs that need
// a post-move fixup after their bytes are relocated.
func swapValues(basePtr: #null *void, valueType: #null typeinfo, indexA, indexB: u64)
{
    if !basePtr or !valueType or indexA == indexB do
        return

    let nnType = valueType
    let size = nnType.sizeof
    let base = cast([*] u8) basePtr
    let pa   = base + indexA * size
    let pb   = base + indexB * size

    let allocator = @getcontext().allocator
    let tmp       = cast(#null [*] u8) Memory.alloc(size, allocator)
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
func appendValueStructArray(arrayPtr: #null *void, valueType: #null typeinfo, defaultInitSlot: bool = true)->#null *void
{
    if !arrayPtr or !valueType
    {
        @panic("Reflection.appendValueStructArray cannot append to a null array or null type", #curlocation)
        return null
    }

    let nnType = valueType
    if defaultInitSlot and !Memory.canDefaultInit(nnType)
    {
        @panic("Reflection.appendValueStructArray cannot default-initialize this type", #curlocation)
        return null
    }

    // We will treat the array as a buffer of bytes, just to be able to access the fields
    let arr       = cast(*Array'u8) arrayPtr
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
        let newBuffer   = cast(#null [*] u8) Memory.alloc(newCapacity * sizeValue, arr.allocator)
        if !newBuffer do
            return null
        let safeNewBuffer = newBuffer
        Memory.clear(safeNewBuffer, newCapacity * sizeValue)

        // Move old values to the new buffer
        Memory.copy(safeNewBuffer, oldBuffer, arr.count * sizeValue)
        if hasPostMove(nnType)
        {
            var buf = safeNewBuffer
            for arr.count
            {
                Memory.postMoveType(buf, nnType)
                buf += sizeValue
            }
        }

        Memory.free(oldBuffer, oldCapacity * sizeValue, arr.allocator)
        arr.buffer = safeNewBuffer
        arr.capacity = newCapacity
    }

    let result = arr.buffer + (arr.count * nnType.sizeof)
    arr.count += 1
    if defaultInitSlot do
        Memory.defaultInit(result, nnType)
    else do
        Memory.clear(notnull result, nnType.sizeof)

    return result
}
