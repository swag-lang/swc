#global private

/**
# Counts and Data Pointers

'.count' returns the logical number of elements in a string, array, slice, enum,
or type that defines 'opCount'. '.buffer' returns the underlying data pointer of
strings, arrays, slices, 'any' values, and interfaces.
*/
#test
{
    var values = [10, 20, 30]

    #assert(values.count == 3)
    Swag.assert(values.buffer == &values[0])
}

/**
# Constructing Non-Owning Views

'Swag.makeSlice(pointer, count)' and 'Swag.makeString(pointer, byteCount)' pair existing
storage with a length. They do not copy or retain that storage, so the result
must not outlive its backing memory.
*/
#test
{
    var bytes = ['S'u8, 'w'u8, 'a'u8, 'g'u8]

    let slice = Swag.makeSlice(&bytes[0], bytes.count)
    let text  = Swag.makeString(&bytes[0], bytes.count)

    #assert(#typeof(slice) == [..] u8)
    Swag.assert(slice.count == 4)
    Swag.assert(text == "Swag")
}

/**
# Constructing and Inspecting 'any'

Ordinary assignment makes an 'any' referring to a value. 'Swag.makeAny' is the
lower-level form: it combines an address and a 'typeinfo'. 'Swag.kindOf' recovers the
stored concrete type and '.buffer' recovers its address.

An 'any' is a view, not an owner: it holds the address of the value it refers to,
so like 'Swag.makeSlice' above, it must not outlive the storage it points at.
*/
#test
{
    var value = 42
    let view  = Swag.makeAny(&value, s32)

    Swag.assert(Swag.kindOf(view) == s32)
    Swag.assert(view.buffer == &value)
    Swag.assert(cast(s32) view == 42)
}

/**
'Swag.makeInterface' and 'Swag.tableOf' are the corresponding low-level building blocks
for interface values. Normal 'cast(MyInterface) value' syntax is safer and
clearer; use the intrinsics only when implementing generic runtime machinery.
*/
