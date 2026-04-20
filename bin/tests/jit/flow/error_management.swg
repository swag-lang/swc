#global fileprivate

struct ErrValue
{
    using base: Swag.BaseError
    code: s32 = 0
}

struct CatchInfo
{
    value: s32
    hasErr: bool
    code: s32
}

var ErrorTrace: s64 = 0

func resetErrorTrace()
{
    ErrorTrace = 0
}

func appendErrorTrace(value: s64)
{
    ErrorTrace = ErrorTrace * 10 + value
}

func mayThrowValue(value: s32 = 42)->s32 throw
{
    return value
}

func mayThrowVoid() throw
{
}

func alwaysThrowValue(code: s32)->s32 throw
{
    throw ErrValue{code: code}
}

func alwaysThrowVoid(code: s32) throw
{
    throw ErrValue{code: code}
}

#[Swag.Inline]
func inlineMayThrowValue(value: s32)->s32 throw
{
    return value
}

#[Swag.Inline]
func inlineAlwaysThrowValue(code: s32)->s32 throw
{
    throw ErrValue{code: code}
}

func propagateBareSuccess()->s32 throw
{
    return mayThrowValue(42)
}

func propagateBareFailure()->s32 throw
{
    return alwaysThrowValue(17)
}

func propagateTrySuccess()->s32 throw
{
    return try mayThrowValue(51)
}

func propagateTryFailure()->s32 throw
{
    return try alwaysThrowValue(18)
}

func propagateTryVoidSuccess() throw
{
    try mayThrowVoid()
}

func propagateTryBlockVoidFailure() throw
{
    try
    {
        try alwaysThrowVoid(21)
    }
}

func catchSuccessValue()->s32
{
    return catch propagateBareSuccess()
}

func catchTrySuccessValue()->s32
{
    return catch propagateTrySuccess()
}

func inlineCatchSuccessValue()->s32
{
    return catch inlineMayThrowValue(63)
}

func catchFailureInfo()->CatchInfo
{
    var result: CatchInfo
    result.value = catch propagateBareFailure()
    result.hasErr = @err != null
    if @err != null
    {
        let err = cast(ErrValue) @err
        result.code = err.code
    }

    return result
}

func inlineCatchFailureInfo()->CatchInfo
{
    var result: CatchInfo
    result.value = catch inlineAlwaysThrowValue(41)
    result.hasErr = @err != null
    if @err != null
    {
        let err = cast(ErrValue) @err
        result.code = err.code
    }

    return result
}

func catchTryFailureInfo()->CatchInfo
{
    var result: CatchInfo
    result.value = catch propagateTryFailure()
    result.hasErr = @err != null
    if @err != null
    {
        let err = cast(ErrValue) @err
        result.code = err.code
    }

    return result
}

func tryCatchFailureInfo()->CatchInfo
{
    var result: CatchInfo
    result.value = trycatch propagateBareFailure()
    result.hasErr = @err != null
    if @err != null
    {
        let err = cast(ErrValue) @err
        result.code = err.code
    }

    return result
}

func inlineTryCatchSuccessValue()->s32
{
    return trycatch inlineMayThrowValue(64)
}

func inlineTryCatchFailureInfo()->CatchInfo
{
    var result: CatchInfo
    result.value = trycatch inlineAlwaysThrowValue(42)
    result.hasErr = @err != null
    if @err != null
    {
        let err = cast(ErrValue) @err
        result.code = err.code
    }

    return result
}

func catchTryVoidSuccess()->bool
{
    catch propagateTryVoidSuccess()
    return @err == null
}

func catchTryBlockVoidFailureCode()->s32
{
    catch propagateTryBlockVoidFailure()
    if @err == null do
        return -1

    let err = cast(ErrValue) @err
    return err.code
}

func nestedTryHandled()->s32
{
    catch
    {
        try alwaysThrowVoid(23)
    }

    if @err == null do
        return -1

    let err = cast(ErrValue) @err
    return err.code
}

#[Swag.Inline]
func traceThrowLeaf() throw
{
    defer appendErrorTrace(1)
    throw ErrValue{code: 31}
}

#[Swag.Inline]
func traceThrowMid() throw
{
    defer appendErrorTrace(2)
    traceThrowLeaf()
}

#[Swag.Inline]
func traceThrowTop() throw
{
    defer appendErrorTrace(4)
    traceThrowMid()
}

func traceThrowCatch()->s64
{
    resetErrorTrace()
    catch traceThrowTop()
    return ErrorTrace
}

func assumeSuccess()->s32
{
    return assume mayThrowValue(77)
}

func tryCatchSuccessValue()->s32
{
    return trycatch propagateTrySuccess()
}

#test
{
    const V = #run catchSuccessValue()
    #assert(V == 42)
}

#test
{
    const V = #run catchTrySuccessValue()
    #assert(V == 51)
}

#test
{
    const V = #run inlineCatchSuccessValue()
    #assert(V == 63)
}

#test
{
    const V = #run catchTryVoidSuccess()
    #assert(V)
}

#test
{
    const V = #run catchFailureInfo()
    #assert(V.value == 0)
    #assert(V.hasErr)
    #assert(V.code == 17)
}

#test
{
    const V = #run inlineCatchFailureInfo()
    #assert(V.value == 0)
    #assert(V.hasErr)
    #assert(V.code == 41)
}

#test
{
    const V = #run catchTryFailureInfo()
    #assert(V.value == 0)
    #assert(V.hasErr)
    #assert(V.code == 18)
}

#test
{
    const V = #run catchTryBlockVoidFailureCode()
    #assert(V == 21)
}

#test
{
    const V = #run tryCatchSuccessValue()
    #assert(V == 51)
}

#test
{
    const V = #run inlineTryCatchSuccessValue()
    #assert(V == 64)
}

#test
{
    const V = #run tryCatchFailureInfo()
    #assert(V.value == 0)
    #assert(!V.hasErr)
    #assert(V.code == 0)
}

#test
{
    const V = #run inlineTryCatchFailureInfo()
    #assert(V.value == 0)
    #assert(!V.hasErr)
    #assert(V.code == 0)
}

#test
{
    const V = #run nestedTryHandled()
    #assert(V == 23)
}

#test
{
    const V = #run traceThrowCatch()
    #assert(V == 124)
}

#test
{
    const V = #run assumeSuccess()
    #assert(V == 77)
}
