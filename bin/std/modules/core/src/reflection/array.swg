#global public
#global namespace Reflection
using Swag

// Returns true if the type 't' is a 'Core.Array' type
func isStructArray(t: typeinfo)->bool
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
func getStructArrayType(t: typeinfo)->#null typeinfo
{
    if !isStructArray(t) do
        return null

    let tt = cast(const *TypeInfoStruct) t
    return tt.generics[0].pointedType
}

// Used to clear a 'Core.Array' without knowing the type of the element at compile time but knowing it at runtime (valueType)
func clearStructArray(arrayPtr: *void, valueType: typeinfo)
{
    let arr = cast(*Array'u8) arrayPtr

    if isStruct(valueType)
    {
        let valueTypeStruct = cast(const *TypeInfoStruct) valueType
        if valueTypeStruct.opDrop
        {
            var scan = arr.buffer
            for x in arr.count
            {
                valueTypeStruct.opDrop(scan)
                scan += valueTypeStruct.sizeof
            }
        }
    }

    arr.count = 0
}

// Remove an element in a 'Core.Array' without knowing the type of the element at compile time but knowing it at runtime (valueType)
func removeValueStructArray(arrayPtr: *void, valueType: typeinfo, index: u64)
{
    // We will treat the array as a buffer of bytes, just to be able to access the fields
    let arr       = cast(*Array'u8) arrayPtr
    let sizeValue = valueType.sizeof

    var valueTypeStruct: const *TypeInfoStruct
    if isStruct(valueType) do
        valueTypeStruct = cast() valueType

    Debug.assert(index < arr.count)

    // Move all elements at the remove position
    if index != arr.count - 1
    {
        let countMove = arr.count - index - 1
        Memory.copy(arr.buffer + (index * sizeValue), arr.buffer + (index + 1) * sizeValue, countMove * sizeValue)
        if valueTypeStruct and Reflection.hasPostMove(valueTypeStruct)
        {
            for i in index until arr.count - 1 do
                valueTypeStruct.opPostMove(arr.buffer + (i * sizeValue))
        }
    }

    // Drop the last element
    if valueTypeStruct and Reflection.hasDrop(valueTypeStruct) do
        valueTypeStruct.opDrop(arr.buffer + (arr.count - 1) * sizeValue)

    arr.count -= 1
}

// Swap two elements (by index) inside a contiguous buffer of 'valueType'. Works for both a
// static array buffer and a 'Core.Array' buffer (pass arr.buffer), handling structs that need
// a post-move fixup after their bytes are relocated.
func swapValues(basePtr: *void, valueType: typeinfo, indexA, indexB: u64)
{
    if indexA == indexB do
        return

    let size = valueType.sizeof
    let base = cast([*] u8) basePtr
    let pa   = base + indexA * size
    let pb   = base + indexB * size

    var valueTypeStruct: const *TypeInfoStruct
    if isStruct(valueType) do
        valueTypeStruct = cast() valueType

    let allocator = @getcontext().allocator
    let tmp       = cast([*] u8) Memory.alloc(size, allocator)
    defer Memory.free(tmp, size, allocator)

    Memory.copy(tmp, pa, size)
    Memory.copy(pa, pb, size)
    Memory.copy(pb, tmp, size)

    // Each element kept its own bytes but landed at a new address: fix up self-references.
    if valueTypeStruct and hasPostMove(valueType)
    {
        valueTypeStruct.opPostMove(pa)
        valueTypeStruct.opPostMove(pb)
    }
}

// Add an element in a 'Core.Array' without knowing the type of the element at compile time but knowing it at runtime (valueType)
func appendValueStructArray(arrayPtr: *void, valueType: typeinfo)->*void
{
    // We will treat the array as a buffer of bytes, just to be able to access the fields
    let arr       = cast(*Array'u8) arrayPtr
    let sizeValue = valueType.sizeof

    var valueTypeStruct: const *TypeInfoStruct
    if isStruct(valueType) do
        valueTypeStruct = cast() valueType

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
        if hasPostMove(valueType)
        {
            var buf = newBuffer
            for arr.count
            {
                valueTypeStruct.opPostMove(buf)
                buf += sizeValue
            }
        }

        Memory.free(oldBuffer, oldCapacity * sizeValue, arr.allocator)
        arr.buffer = newBuffer
        arr.capacity = newCapacity
    }

    let result = arr.buffer + (arr.count * valueType.sizeof)
    arr.count += 1
    if valueTypeStruct and valueTypeStruct.opInit do
        valueTypeStruct.opInit(result)
    else do
        Memory.clear(result, sizeValue)

    return result
}
