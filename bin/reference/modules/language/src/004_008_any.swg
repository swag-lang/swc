#global private

/**
# The 'any' Type in Swag

'any' is a dynamically typed view that can point to a value of any concrete type.

> WARNING:
> 'any' is **not** a variant. It holds the address of an existing value plus its runtime type
> info. Assigning to an 'any' never copies the value, so an 'any' is a view for the purposes
> of the borrow rules, and must not outlive the storage it refers to. See the 'Borrowing'
> section.
*/

#test
{
    var a: #null any

    // Store an s32 literal value in the 'any'
    a = 6
    Swag.assert(cast(s32) a == 6)

    // Now store a string
    a = "string"
    Swag.assert(cast(string) a! == "string")

    // Now store a bool
    a = true
    Swag.assert(cast(bool) a == true)
}

/**
# Working with 'any' and Pointers

Use '.buffer' to access a pointer to the underlying value stored inside 'any'.
*/

#test
{
    let a: any = 6
    let ptr    = cast(const *s32) a.buffer
    Swag.assert(ptr[] == 6)
}

/**
# Type Information and 'any'

'#typeof' on an 'any' yields 'any' (the type of the view itself).
Use 'Swag.kindOf' to get the concrete runtime type of the viewed value.
*/

#test
{
    var a: any = "string"
    #assert(#typeof(a) == any)
    Swag.assert(Swag.kindOf(a) == string)

    a = true
    Swag.assert(Swag.kindOf(a) == bool)
}

/**
# Retrieving Values from 'any'

You can retrieve the stored value directly or through a constant pointer.
*/

#test
{
    let a: any = 42
    #assert(#typeof(a) == any)
    Swag.assert(Swag.kindOf(a) == s32)

    let b = cast(s32) a     // Get the value itself
    Swag.assert(b == 42)

    let d = cast(const *s32) a     // Get a constant pointer to the value
    Swag.assert(d[] == 42)
}

/**
# Arrays of 'any'

You can create heterogeneous arrays where each element holds a different type.
*/

#test
{
    var array: [?] any = [true, 2, 3.0, "4"]

    Swag.assert(Swag.kindOf(array[0]) == bool)
    Swag.assert(Swag.kindOf(array[1]) == s32)
    Swag.assert(Swag.kindOf(array[2]) == f32)
    Swag.assert(Swag.kindOf(array[3]) == string)

    Swag.assert(cast(bool) array[0] == true)
    Swag.assert(cast(s32) array[1] == 2)
    Swag.assert(cast(f32) array[2] == 3.0)
    Swag.assert(cast(string) array[3] == "4")
}

/**
# Nullability of 'any'

An 'any' value can be null, similar to pointers and other nullable types.
*/

#test
{
    var x: #null any
    Swag.assert(x == null)

    x = 6
    Swag.assert(x != null)
    Swag.assert(cast(s32) x == 6)

    x = "string"
    Swag.assert(x != null)
    Swag.assert(cast(string) x! == "string")

    x = null
    Swag.assert(x == null)
}

/**
# Type Checking with 'any'

An 'any' can be compared to a type using '==' or '!='.
This uses 'Swag.kindOf' internally to compare the stored value's type.
*/

#test
{
    var x: #null any
    Swag.assert(x == null)

    x = 6
    Swag.assert(x == s32)
    Swag.assert(x != bool)

    x = "string"
    Swag.assert(x != s32)
    Swag.assert(x == string)

    struct A {}
    x = A{}
    Swag.assert(x == A)
}
