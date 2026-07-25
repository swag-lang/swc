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
'catch' handles the error locally, returns the default value for the result
type, and exposes the captured error through '@err'.
*/
#test
{
    let value = catch count(null)
    @assert(value == 0)
    @assert(@err != null)

    let err = cast(MyError) @err
    @assert(err.code == 7)
    @assert(err.message == "name cannot be null")
}

/**
# Handling on Failure with 'catch ... else'
'catch e else { H }' runs the handler 'H' only when 'e' fails, replacing the
'catch e; if @err != null do H' pattern. Inside 'H' the caught error is available
through '@err'. 'H' is evaluated lazily — only on the failure path — and may divert
control flow (e.g. an early 'return').
*/
func recordTrace(name: #null string, out: *s32) fail
{
    dref out = cast(s32) count(name)
}

#test
{
    var seen: s32 = -1
    catch recordTrace("swag", &seen) else
    {
        seen = (cast(MyError) @err).code
    }
    @assert(seen == 4)          // success: handler skipped, value recorded

    catch recordTrace(null, &seen) else
    {
        seen = (cast(MyError) @err).code
    }
    @assert(seen == 7)          // failure: handler ran, '@err' readable
}

/**
# Dismissing Errors
To dismiss a failure and continue, hand the fallible call to 'orfail' with a
fallback value (see below). '@err' is cleared, and the expression yields the
fallback instead of the error.
*/
func safeCount(name: #null string)->u64
{
    return count(name) orfail 0
}

#test
{
    @assert(safeCount("hello") == 5)
    @assert(@err == null)
    @assert(safeCount(null) == 0)
    @assert(@err == null)
}

/**
# Fallback Value with 'orfail'
'e orfail V' catches a failure in the fallible expression 'e' and yields the
fallback 'V' instead, dismissing the error. The fallback is an explicit value (it
need not be the type default), and it is evaluated **lazily** — only when 'e'
actually fails.
*/
#test
{
    let a = count("swag") orfail 99
    @assert(a == 4)

    let b = count(null) orfail 99
    @assert(b == 99)
    @assert(@err == null)     // 'orfail' dismisses the error
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
    let value = catch propagateCount("abc")
    @assert(value == 3)
    @assert(@err == null)
}

#test
{
    let value = catch propagateCount(null)
    @assert(value == 0)
    @assert(@err != null)

    let err = cast(MyError) @err
    @assert(err.code == 7)
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
    let value = catch implicitTryCount(null)
    @assert(value == 0)
    @assert(@err != null)

    let err = cast(MyError) @err
    @assert(err.code == 7)
}

/**
# Error-Handling Blocks
'try', 'catch' (optionally with 'else'), and 'expect' can also guard a whole
block of code.
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
    }

    if @err == null do
        return -1

    let err = cast(MyError) @err
    return err.code
}

func blockCatchElse(name: #null string)->u64
{
    catch
    {
        return count(name)
    } else {}

    return 99
}

#test
{
    let value = catch blockTry("ab", null)
    @assert(value == 0)
    @assert(@err != null)
    let err = cast(MyError) @err
    @assert(err.code == 7)
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
    let value = catch deferOnFail(null)
    @assert(value == 0)
    @assert(DeferTrace == 1)
}
