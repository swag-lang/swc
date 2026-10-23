#global private

// A local capture belongs to the failure handler. An explicit Swag.Error owner
// retains an error for later inspection and becomes empty on success.

struct CatchAsErrError
{
    using base: Swag.BaseError
    code:       s32 = 0
}

func catchAsErrMayFail(ok: bool) fail
{
    if not ok do
        fail CatchAsErrError{base: Swag.BaseError{"boom"}, code: 7}
}

func catchAsErrCount(ok: bool)->s32 fail
{
    if not ok do
        fail CatchAsErrError{base: Swag.BaseError{"boom"}, code: 7}
    return 42
}

// Statement form: capture, then branch on the named error.
func catchAsErrRun(ok: bool)->s32
{
    catch catchAsErrMayFail(ok) as err else { return assume cast(CatchAsErrError, err).code }
    return 1000
}

// A value expression either succeeds or returns from its failure handler.
func catchAsErrValue(ok: bool)->s32
{
    let x = catch catchAsErrCount(ok) as err else { return -assume cast(CatchAsErrError, err).code }
    return x
}

#test
{
    Swag.assert(catchAsErrRun(true) == 1000)
    Swag.assert(catchAsErrRun(false) == 7)
}

#test
{
    Swag.assert(catchAsErrValue(true) == 42)
    Swag.assert(catchAsErrValue(false) == -7)
}

// An explicit owner keeps its runtime lowering when an inline fallible call folds
// to a constant: the successful catch must still clear a previous stored error.
#[Swag.Inline]
func catchAsErrInlineFoldable(value: s32)->s32 fail
{
    return value
}

#test
{
    var errOutcome: Swag.Error
    let x   = catch catchAsErrInlineFoldable(63) as &errOutcome else 0
    let err = errOutcome.value()
    Swag.assert(x == 63)
    Swag.assert(err == null)
}

#test
{
    // Same through the statement form, where the result is discarded entirely.
    var errOutcome: Swag.Error
    discard catch catchAsErrInlineFoldable(11) as &errOutcome
    let err = errOutcome.value()
    Swag.assert(err == null)
}

#[Swag.Inline]
func catchAsErrInlineVoid() fail {}

func catchAsErrInlineCaptures()
{
    // Void inline callee: the statement and block forms of the capture.
    var errOutcome: Swag.Error
    catch catchAsErrInlineVoid() as &errOutcome
    let err = errOutcome.value()
    Swag.assert(err == null)

    var err2Outcome: Swag.Error
    discard catch catchAsErrInlineFoldable(9) as &err2Outcome
    let err2 = err2Outcome.value()
    Swag.assert(err2 == null)
}

#test
{
    catchAsErrInlineCaptures()
}

// The captured error is dismissed after the catch, so a following fallible flow starts clean;
// re-raising a saved outcome is explicit via its owner.
func catchAsErrReraise(ok: bool)->s32 fail
{
    var errOutcome: Swag.Error
    catch catchAsErrMayFail(ok) as &errOutcome
    if not errOutcome.isEmpty() and ok == false do
        try errOutcome.raise()
    return 5
}

#test
{
    Swag.assert(catch catchAsErrReraise(true) == 5 else false)
    var seen = 0
    discard catch catchAsErrReraise(false) as err else { seen = assume cast(CatchAsErrError, err).code }
    Swag.assert(seen == 7)
}

var catchAsErrFailDeferCount: s32

func catchAsErrNestedExpectSuccess() fail
{
    discard expect catchAsErrCount(true)
}

func catchAsErrSuccessWithFailDefer() fail
{
    defer #fail catchAsErrFailDeferCount += 1
    try catchAsErrNestedExpectSuccess()
}

#test
{
    // Reusing an error-stack slot after a handled capture must not restore the old error when a
    // nested `expect` succeeds; in particular, the surrounding successful frame stays no-fail.
    var previousErrorOutcome: Swag.Error
    catch catchAsErrMayFail(false) as &previousErrorOutcome
    let previousError = previousErrorOutcome.value()
    Swag.assert(previousError != null)

    catchAsErrFailDeferCount = 0
    discard expect catchAsErrSuccessWithFailDefer()
    Swag.assert(catchAsErrFailDeferCount == 0)
}
