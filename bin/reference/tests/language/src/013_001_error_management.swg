#global fileprivate
/**
# Error Management
Swag models errors as values. A function marked with 'throw' can either return
its normal result or exit early with 'throw errorValue'. The caller then chooses
whether to propagate, catch, dismiss, or assume success.
*/

struct MyError
{
    using base: Swag.BaseError
    code: s32 = 0
}

func count(name: string)->u64 throw
{
    if name == null do
        throw MyError{base: Swag.BaseError{"name cannot be null"}, code: 7}
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
# Dismissing Errors
'trycatch' dismisses the error and continues execution. The result becomes the
default value of the returned type and '@err' is cleared.
*/
func safeCount(name: string)->u64
{
    return trycatch count(name)
}

#test
{
    @assert(safeCount("hello") == 5)
    @assert(@err == null)
    @assert(safeCount(null) == 0)
    @assert(@err == null)
}

/**
# Propagating Errors
'try' propagates the current error to the caller, so it belongs inside a
function that can itself return an error.
*/
func propagateCount(name: string)->u64 throw
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
Inside a function declared with 'throw', calling another throwing function is
an implicit propagation.
*/
func implicitTryCount(name: string)->u64 throw
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
'try', 'catch', 'trycatch', and 'assume' can also guard a whole block of code.
*/
func blockTry(name0: string, name1: string)->u64 throw
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

func blockTryCatch(name: string)->u64
{
    trycatch
    {
        return count(name)
    }

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
    @assert(blockTryCatch("abcd") == 4)
    @assert(blockTryCatch(null) == 99)
}

/**
# Assume
Inside '#test', 'try' is equivalent to 'assume', so both forms keep the
success path concise when failure is not expected.
*/
#test
{
    let value = try count("swag")
    @assert(value == 4)
}

#test
{
    let value = assume count("swag")
    @assert(value == 4)
}

/**
# Defer on Error Paths
A plain 'defer' still runs when a function exits through 'throw', because
'throw' is an early return carrying an error value.
*/
var DeferTrace: s32 = 0

func deferOnThrow(name: string)->u64 throw
{
    defer DeferTrace += 1
    return try count(name)
}

#test
{
    DeferTrace = 0
    let value = catch deferOnThrow(null)
    @assert(value == 0)
    @assert(DeferTrace == 1)
}
