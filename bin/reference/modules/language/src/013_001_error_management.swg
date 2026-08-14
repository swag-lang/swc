#global private

/**
# Error Management
Swag models errors as values. A function marked with 'fail' can either return
its normal result or exit early with 'fail errorValue'. The caller then chooses
whether to propagate, catch, dismiss, or expect success.
*/

struct MyError
{
    using base: Swag.BaseError
    code:       s32 = 0
}

func count(name: #null string)->u64 fail
{
    if name == null do
        fail MyError{base: Swag.BaseError{"name cannot be null"}, code: 7}
    return @countof(name)
}

/**
# Catching Errors
'catch' handles the error locally and returns the default value for the result
type. To inspect the error, capture it with 'as err': this binds a fresh local
(of type '#null any') that is null on success and holds the caught error on
failure. The capture is visible in the enclosing scope, after the catch, so each
capture in a given scope needs its own name.
*/
#test
{
    let value = catch count(null) as err
    @assert(value == 0)
    @assert(err != null)

    let e = cast(MyError) err
    @assert(e.code == 7)
    @assert(e.message == "name cannot be null")
}

/**
# Handling on Failure with 'catch ... else'
'catch e else { H }' runs the anonymous handler 'H' only when 'e' fails. 'H'
cannot inspect the error (capture it with 'as err' for that); it is evaluated
lazily — only on the failure path — and may divert control flow (e.g. an early
'return'). To read the caught error, use the 'as err' capture form instead.
*/
func recordTrace(name: #null string, out: *s32) fail
{
    out[] = cast(s32) count(name)
}

#test
{
    var seen: s32 = -1

    catch recordTrace("swag", &seen) else do
        seen = -2
    @assert(seen == 4)     // success: the handler does not run

    catch recordTrace(null, &seen) else
    {
        seen = -2
    }

    @assert(seen == -2)     // failure: the handler ran instead
}

/**
# Dismissing Errors
To dismiss a failure and continue with the type default, use 'catch' without a
capture: the error is handled and dropped, and the expression yields the default
value for the result type. To keep the error, add an 'as err' capture; to use a
custom fallback, capture and branch ('var x = catch f() as err; if err != null do x = V').
*/
func safeCount(name: #null string)->u64
{
    return catch count(name)
}

#test
{
    @assert(safeCount("hello") == 5)
    @assert(safeCount(null) == 0)
}

/**
# Propagating Errors
'try' propagates the current error to the caller, so it belongs inside a
function that can itself return an error.
*/
func propagateCount(name: #null string)->u64 fail
{
    return try count(name)
}

#test
{
    let value = catch propagateCount("abc") as err
    @assert(value == 3)
    @assert(err == null)
}

#test
{
    let value = catch propagateCount(null) as err
    @assert(value == 0)
    @assert(err != null)
    @assert((cast(MyError) err).code == 7)
}

/**
# Implicit try
Inside a function declared with 'fail', calling another fallible function is
an implicit propagation.
*/
func implicitTryCount(name: #null string)->u64 fail
{
    return count(name)
}

#test
{
    let value = catch implicitTryCount(null) as err
    @assert(value == 0)
    @assert(err != null)
    @assert((cast(MyError) err).code == 7)
}

/**
# Error-Handling Blocks
'try', 'catch' (optionally with 'as err' or 'else'), and 'expect' can also guard
a whole block of code.
*/
func blockTry(name0: #null string, name1: #null string)->u64 fail
{
    var total: u64 = 0
    try
    {
        total += count(name0)
        total += count(name1)
    }

    return total
}

func blockCatchCode()->s32
{
    catch
    {
        discard count("ok")
        discard count(null)
    } as err

    if err == null do
        return -1

    return (cast(MyError) err).code
}

func blockCatchElse(name: #null string)->u64
{
    catch
    {
        return count(name)
    }
    else {}

    return 99
}

#test
{
    let value = catch blockTry("ab", null) as err
    @assert(value == 0)
    @assert(err != null)
    @assert((cast(MyError) err).code == 7)
}

#test
{
    @assert(blockCatchCode() == 7)
    @assert(blockCatchElse("abcd") == 4)
    @assert(blockCatchElse(null) == 99)
}

/**
# Expect
Inside '#test', 'try' is equivalent to 'expect', so both forms keep the
success path concise when failure is not expected.
*/
#test
{
    let value = try count("swag")
    @assert(value == 4)
}

#test
{
    let value = expect count("swag")
    @assert(value == 4)
}

/**
# Defer on Error Paths
A plain 'defer' still runs when a function exits through 'fail', because
'fail' is an early return carrying an error value.
*/
var DeferTrace: s32 = 0

func deferOnFail(name: #null string)->u64 fail
{
    defer DeferTrace += 1
    return try count(name)
}

#test
{
    DeferTrace = 0
    let value = catch deferOnFail(null) as err
    @assert(value == 0)
    @assert(err != null)
    @assert(DeferTrace == 1)
}
