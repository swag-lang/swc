#global private

// A fallible function whose result is wider than the error it fails with: the fail
// expression's runtime storage serves both the error value and the synthesized zero
// result, so it must be sized for the wider of the two. Sized for the error alone, the
// result zeroing trampled the frame past the slot (512 zero bytes into a 3-pointer
// slot), smashing the saved return storage pointer.
struct WideError
{
    using base: Swag.BaseError
}

struct Small
{
    a, b: u64
}

struct Big
{
    data: [64] u64
}

func makeSmall(ok: bool)->Small fail
{
    if !ok do
        fail WideError{base: Swag.BaseError{"nope"}}
    var result: retval
    result.a = 1
    return result
}

func makeBig(ok: bool)->Big fail
{
    if !ok do
        fail WideError{base: Swag.BaseError{"nope"}}
    var result: retval
    result.data[0]  = 1
    result.data[63] = 2
    return result
}

#test
{
    var v = catch makeSmall(false) as err
    Swag.assert(err != null)
    Swag.assert(v.a == 0)
}

#test
{
    var v = catch makeBig(false) as err
    Swag.assert(err != null)
    Swag.assert(v.data[0] == 0)
    Swag.assert(v.data[63] == 0)
}

#test
{
    var v = catch makeBig(true) as err
    Swag.assert(err == null)
    Swag.assert(v.data[0] == 1)
    Swag.assert(v.data[63] == 2)
}
