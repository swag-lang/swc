#global private

/**
# The `retval` Special Type
In Swag, `retval` represents the current function’s return type.
It allows you to declare and manipulate the return value directly inside the function,
without repeating the type declaration. This improves code readability and flexibility,
especially when working with complex or generic return types.
*/
#test
{
    func toto()->s32
    {
        var result: retval     // 'retval' resolves to 's32' in this context.
        result = 10
        return result
    }

    @assert(toto() == 10)
}

/**
# Optimizing Return Values
A `retval` local *is* the return value: the compiler gives it the caller’s memory, so filling
it in costs no copy at the end of the function.
This is especially beneficial when returning large structs, arrays, or tuples.

Returning an aggregate literal needs no annotation for this — `return RGB{0.5, 0.1, 1.0}` is
already built in the caller’s memory. Reach for `retval` when the value is filled in step by
step, or when the return type has no name you could write.
*/
#test
{
    struct RGB
    {
        x, y, z: f64
    }

    func getWhite()->RGB
    {
        // 'retval = undefined' prevents unnecessary clearing of the return structure.
        var result: retval = undefined
        result.x = 0.5
        result.y = 0.1
        result.z = 1.0
        return result
    }

    let {r, g, b} = getWhite()
    @assert(r == 0.5)
    @assert(g == 0.1)
    @assert(b == 1.0)
}

/**
# Returning Arrays Efficiently
When returning large data structures like arrays, using `retval` avoids redundant
initialization or copying, resulting in faster, more memory-efficient code.
*/
#test
{
    func toto()->[255] s32
    {
        var result: retval = undefined
        for [i] in 255 do
            result[i] = i
        return result
    }

    var arr = toto()
    @assert(arr[0] == 0)
    @assert(arr[100] == 100)
    @assert(arr[254] == 254)
}
