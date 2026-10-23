#global private

// A fallible function can fail with an error narrower than its result. An explicit
// aggregate fallback must fill the result storage without overwriting the smaller
// error slot or its saved return-storage pointer.
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
    if not ok do
        fail WideError{base: Swag.BaseError{"nope"}}
    var result: retval
    result.a = 1
    return result
}

func makeBig(ok: bool)->Big fail
{
    if not ok do
        fail WideError{base: Swag.BaseError{"nope"}}
    var result: retval
    result.data[0]  = 1
    result.data[63] = 2
    return result
}

#test
{
    var errOutcome: Swag.Error
    let v   = catch makeSmall(false) as &errOutcome else Small{}
    let err = errOutcome.value()
    Swag.assert(err != null)
    Swag.assert(v.a == 0)
}

#test
{
    var errOutcome: Swag.Error
    let v   = catch makeBig(false) as &errOutcome else Big{}
    let err = errOutcome.value()
    Swag.assert(err != null)
    Swag.assert(v.data[0] == 0)
    Swag.assert(v.data[63] == 0)
}

#test
{
    var errOutcome: Swag.Error
    let v   = catch makeBig(true) as &errOutcome else Big{}
    let err = errOutcome.value()
    Swag.assert(err == null)
    Swag.assert(v.data[0] == 1)
    Swag.assert(v.data[63] == 2)
}
