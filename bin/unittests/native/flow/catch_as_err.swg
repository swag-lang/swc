#global private

// 'catch e as err' captures the caught error into a fresh local 'err' (of type '#null any')
// bound in the ENCLOSING scope: null when the fallible operand succeeds, the caught error when
// it fails (dismissed afterwards). It replaces the removed ambient error intrinsic — the error is now
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

// An 'as err' capture keeps its runtime lowering even when the operand folds to a compile-time
// constant. An inlined fallible call whose body is a plain 'return value' folds to that value; if
// the node collapsed onto the constant, codegen would emit the constant INSTEAD of the fallible
// wrapper and never seed the capture slot, so 'err' would read back uninitialized stack.
#[Swag.Inline]
func catchAsErrInlineFoldable(value: s32)->s32 fail
{
    return value
}

#test
{
    let x = catch catchAsErrInlineFoldable(63) as err
    @assert(x == 63)
    @assert(err == null)
}

#test
{
    // Same through the statement form, where the result is discarded entirely.
    discard catch catchAsErrInlineFoldable(11) as err
    @assert(err == null)
}

#[Swag.Inline]
func catchAsErrInlineVoid() fail {}

#test
{
    // Void inline callee: the statement and block forms of the capture.
    catch catchAsErrInlineVoid() as err
    @assert(err == null)

    catch { discard catchAsErrInlineFoldable(9) } as err2
    @assert(err2 == null)
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

var catchAsErrFailDeferCount: s32

func catchAsErrNestedExpectSuccess() fail
{
    discard expect catchAsErrCount(true)
}

func catchAsErrSuccessWithFailDefer() fail
{
    defer #fail catchAsErrFailDeferCount += 1
    catchAsErrNestedExpectSuccess()
}

#test
{
    // Reusing an error-stack slot after a handled capture must not restore the old error when a
    // nested `expect` succeeds; in particular, the surrounding successful frame stays no-fail.
    catch catchAsErrMayFail(false) as previousError
    @assert(previousError != null)

    catchAsErrFailDeferCount = 0
    discard expect catchAsErrSuccessWithFailDefer()
    @assert(catchAsErrFailDeferCount == 0)
}
