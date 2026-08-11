#global private

/**
# Counts and Data Pointers

'@countof' returns the logical number of elements in a string, array, slice, enum,
or type that defines 'opCount'. '@dataof' returns the underlying data pointer of
strings, arrays, slices, 'any' values, and interfaces.
*/
#test
{
    var values = [10, 20, 30]

    #assert(@countof(values) == 3)
    @assert(@dataof(values) == &values[0])
}

/**
# Constructing Non-Owning Views

'@mkslice(pointer, count)' and '@mkstring(pointer, byteCount)' pair existing
storage with a length. They do not copy or retain that storage, so the result
must not outlive its backing memory.
*/
#test
{
    var bytes = ['S'u8, 'w'u8, 'a'u8, 'g'u8]

    let slice = @mkslice(&bytes[0], @countof(bytes))
    let text  = @mkstring(&bytes[0], @countof(bytes))

    #assert(#typeof(slice) == [..] u8)
    @assert(@countof(slice) == 4)
    @assert(text == "Swag")
}

/**
# Constructing and Inspecting 'any'

Ordinary assignment makes an 'any' referring to a value. '@mkany' is the
lower-level form: it combines an address and a 'typeinfo'. '@kindof' recovers the
stored concrete type and '@dataof' recovers its address.

An 'any' is a view, not an owner: it holds the address of the value it refers to,
so like '@mkslice' above, it must not outlive the storage it points at.
*/
#test
{
    var value = 42
    let view  = @mkany(&value, s32)

    @assert(@kindof(view) == s32)
    @assert(@dataof(view) == &value)
    @assert(cast(s32) view == 42)
}

/**
'@mkinterface' and '@tableof' are the corresponding low-level building blocks
for interface values. Normal 'cast(MyInterface) value' syntax is safer and
clearer; use the intrinsics only when implementing generic runtime machinery.
*/
