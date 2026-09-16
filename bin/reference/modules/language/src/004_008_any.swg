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
    var a: any?

    // Store an s32 literal value in the 'any'
    a = 6
    Swag.assert(cast #assume(s32) a == 6)

    // Now store a string
    a = "string"
    Swag.assert(cast #assume (string) a! == "string")

    // Now store a bool
    a = true
    Swag.assert(cast #assume (bool) a == true)
}

/**
# Working with 'any' and Pointers

Use `cast #try (*T)` to borrow the stored value after checking its type.
*/

#test
{
    let a: any = 6
    let ptr    = cast #try (const *s32) a
    Swag.assert(ptr != null)
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

    let b = cast #assume(s32) a     // Get the value itself
    Swag.assert(b == 42)

    let d = cast #assume (const *s32) a     // Get a constant pointer to the value
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

    Swag.assert(cast #assume(bool) array[0] == true)
    Swag.assert(cast #assume (s32) array[1] == 2)
    Swag.assert(cast #assume (f32) array[2] == 3.0)
    Swag.assert(cast #assume (string) array[3] == "4")
}

/**
# Nullability of 'any'

An 'any?' value can be null and defaults to that absent state. A bare 'any'
requires a value. Prove presence before inspecting or converting a nullable
value, just as for pointers and other nullable types.
*/

#test
{
    var x: any?
    Swag.assert(x == null)

    x = 6
    Swag.assert(x != null)
    Swag.assert(cast #assume(s32) x == 6)

    x = "string"
    Swag.assert(x != null)
    Swag.assert(cast #assume (string) x == "string")

    x = null
    Swag.assert(x == null)
}

/**
# Type Checking with 'any'

Use `value is T` to test whether the stored value can be viewed as `T`.
Use `if value is T as name` when the branch also needs to access the value.
*/

#test
{
    var x: any?
    Swag.assert(x == null)

    x = 6
    Swag.assert(x is s32)
    Swag.assert(not (x is bool))

    x = "string"
    Swag.assert(not (x is s32))
    Swag.assert(x is string)

    struct A {}
    x = A{}
    Swag.assert(x is A)
}
