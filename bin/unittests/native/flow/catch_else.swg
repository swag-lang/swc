#global private

// 'catch e else { H }' runs the handler H only when the fallible statement 'e' fails,
// dismissing the boilerplate 'catch e; if @err != null do H'. Inside H the caught error
// stays reachable through '@err'. The handler is emitted lazily on the failure path.

struct CatchElseError
{
    using base: Swag.BaseError
    code:       s32 = 0
}

func catchElseMayFail(ok: bool) fail
{
    if !ok do
        fail CatchElseError{base: Swag.BaseError{"boom"}, code: 42}
}

var g_catchElseTrace = 0

func catchElseRun(ok: bool)->s32
{
    g_catchElseTrace = 0
    catch catchElseMayFail(ok) else
    {
        g_catchElseTrace = 1
        let e            = cast(CatchElseError) @err
        g_catchElseTrace = e.code
    }
    g_catchElseTrace += 1000
    return g_catchElseTrace
}

func catchElseEarlyReturn(ok: bool)->s32
{
    catch catchElseMayFail(ok) else do
        return -1
    return 100
}

// Success skips the handler; failure runs it with '@err' readable, then execution
// continues after the construct.
#test
{
    @assert(catchElseRun(true) == 1000)
    @assert(catchElseRun(false) == 42 + 1000)
}

// The handler may divert control flow (early return on failure).
#test
{
    @assert(catchElseEarlyReturn(true) == 100)
    @assert(catchElseEarlyReturn(false) == -1)
}
