#global private

// 'catch e as err { H }' is the named form of 'catch e else { H }': it runs the handler H
// only when the fallible statement 'e' fails, but binds the caught error into a fresh local
// 'err' (of type '#null any') visible inside H, instead of reading it through '@err'. The
// binding is scoped to the handler and holds its own copy, so it survives the post-handler
// dismissal of the in-flight error.

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

var g_catchAsErrTrace = 0

func catchAsErrRun(ok: bool)->s32
{
    g_catchAsErrTrace = 0
    catch catchAsErrMayFail(ok) as err
    {
        g_catchAsErrTrace = 1
        let e             = cast(CatchAsErrError) err
        g_catchAsErrTrace = e.code
    }
    g_catchAsErrTrace += 1000
    return g_catchAsErrTrace
}

func catchAsErrEarlyReturn(ok: bool)->s32
{
    catch catchAsErrMayFail(ok) as err do
        return err != null ? -1 : -2
    return 100
}

// Success skips the handler; failure runs it with 'err' bound to the caught error, then
// execution continues after the construct.
#test
{
    @assert(catchAsErrRun(true) == 1000)
    @assert(catchAsErrRun(false) == 7 + 1000)
}

// The named binding works in a single-statement handler that diverts control flow too.
#test
{
    @assert(catchAsErrEarlyReturn(true) == 100)
    @assert(catchAsErrEarlyReturn(false) == -1)
}

// After the handler runs, the in-flight error is dismissed (like 'catch..else'), so a
// following '@err' check sees no error.
#test
{
    catch catchAsErrMayFail(false) as err
    {
        @assert(err != null)
    }
    @assert(@err == null)
}
