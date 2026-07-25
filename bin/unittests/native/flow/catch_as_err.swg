#global private

// 'catch e as err' captures the caught error into a fresh local 'err' (of type '#null any')
// bound in the ENCLOSING scope: null when the fallible operand succeeds, the caught error when
// it fails (dismissed afterwards). It replaces the removed '@err' intrinsic — the error is now
// always obtained by an explicit named capture, never a global. Works as a statement and, in
// expression position, as 'let x = catch f() as err' (result + captured error together).

struct CatchAsErrError
{
    using base: Swag.BaseError
    code:       s32 = 0
}

func catchAsErrMayFail(ok: bool) fail
{
    if !ok do
        fail CatchAsErrError{base: Swag.BaseError{"boom"}, code: 7}
}

func catchAsErrCount(ok: bool)->s32 fail
{
    if !ok do
        fail CatchAsErrError{base: Swag.BaseError{"boom"}, code: 7}
    return 42
}

// Statement form: capture, then branch on the named error.
func catchAsErrRun(ok: bool)->s32
{
    catch catchAsErrMayFail(ok) as err
    if err != null do
        return (cast(CatchAsErrError) err).code
    return 1000
}

// Expression form: 'x' is the result (default on failure), 'err' the captured error.
func catchAsErrValue(ok: bool)->s32
{
    let x = catch catchAsErrCount(ok) as err
    if err != null do
        return -(cast(CatchAsErrError) err).code
    return x
}

#test
{
    @assert(catchAsErrRun(true) == 1000)
    @assert(catchAsErrRun(false) == 7)
}

#test
{
    @assert(catchAsErrValue(true) == 42)
    @assert(catchAsErrValue(false) == -7)
}

// The captured error is dismissed after the catch, so a following fallible flow starts clean;
// re-raising is explicit via 'fail err'.
func catchAsErrReraise(ok: bool)->s32 fail
{
    catch catchAsErrMayFail(ok) as err
    if err != null and ok == false do
        fail err
    return 5
}

#test
{
    @assert(catch catchAsErrReraise(true) == 5)
    var seen = 0
    discard catch catchAsErrReraise(false) as err
    if err != null do
        seen = (cast(CatchAsErrError) err).code
    @assert(seen == 7)
}
