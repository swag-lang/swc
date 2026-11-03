#global private

// 'catch e else { H }' runs the anonymous handler H only when the fallible statement 'e' fails.
// H cannot inspect the error (use 'catch e as err' for that); it is emitted lazily on the failure
// path and may divert control flow. To read the caught error, capture it with 'as err'.

struct CatchElseError
{
    using base: Swag.BaseError
    code:       s32 = 0
}

func catchElseMayFail(ok: bool) fail
{
    if not ok do
        fail CatchElseError{base: Swag.BaseError{"boom"}, code: 42}
}

var g_catchElseTrace = 0

// Capture form: read the caught error by name on the failure path.
func catchElseRun(ok: bool)->s32
{
    g_catchElseTrace = 0
    catch catchElseMayFail(ok)
    {
        g_catchElseTrace = 1
        let e = assume cast(CatchElseError, Swag.err)
        g_catchElseTrace = e.code
    }
    g_catchElseTrace += 1000
    return g_catchElseTrace
}

// Anonymous 'else' handler: diverts control flow on failure without inspecting the error.
func catchElseEarlyReturn(ok: bool)->s32
{
    catch catchElseMayFail(ok) do
        return -1
    return 100
}

// Success skips the handler; failure runs it, then execution continues after the construct.
#test
{
    Swag.require(catchElseRun(true) == 1000)
    Swag.require(catchElseRun(false) == 42 + 1000)
}

// The anonymous handler may divert control flow (early return on failure).
#test
{
    Swag.require(catchElseEarlyReturn(true) == 100)
    Swag.require(catchElseEarlyReturn(false) == -1)
}

var g_catchElseHandlerRuns = 0

func catchElseBump() { g_catchElseHandlerRuns += 1 }

// A handler that is a single inlined call still runs on the failure path only.
#test
{
    g_catchElseHandlerRuns = 0
    catch catchElseMayFail(true) do catchElseBump()
    Swag.require(g_catchElseHandlerRuns == 0)
    catch catchElseMayFail(false) do catchElseBump()
    Swag.require(g_catchElseHandlerRuns == 1)
}
