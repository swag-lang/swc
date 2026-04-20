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

func propagateBareVoidFailure() throw
{
    alwaysThrowVoid(19)
}

func propagateTryBlockVoidFailure() throw
{
    try
    {
        try alwaysThrowVoid(21)
    }
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

func recordAssumePanic(message: string, loc: SourceCodeLocation)
{
    let cxt = @getcontext()
    cxt.user0 += 1
    cxt.user1 = cast(u64) loc.lineStart
}

func assumeFailureInfo()->CatchInfo
{
    let cxt = @getcontext()
    cxt.user0 = 0
    cxt.user1 = 0
    cxt.panic = &recordAssumePanic
    defer cxt.panic = null

    var result: CatchInfo
    result.value = assume alwaysThrowValue(29)
    result.hasErr = cxt.user0 == 1
    result.code = cast(s32) cxt.user1
    return result
}

#test
{
    let value = catch propagateBareSuccess()
    @assert(value == 42)
    @assert(@err == null)
}

#test
{
    let value = catch propagateTrySuccess()
    @assert(value == 51)
    @assert(@err == null)
}

#test
{
    let value = catch inlineMayThrowValue(63)
    @assert(value == 63)
    @assert(@err == null)
}

#test
{
    catch propagateTryVoidSuccess()
    @assert(@err == null)
}

#test
{
    let info = catchFailureInfo()
    @assert(info.value == 0)
    @assert(info.hasErr)
    @assert(info.code == 17)
}

#test
{
    let info = inlineCatchFailureInfo()
    @assert(info.value == 0)
    @assert(info.hasErr)
    @assert(info.code == 41)
}

#test
{
    let info = catchTryFailureInfo()
    @assert(info.value == 0)
    @assert(info.hasErr)
    @assert(info.code == 18)
}

#test
{
    catch propagateBareVoidFailure()
    @assert(@err != null)
    let err = cast(ErrValue) @err
    @assert(err.code == 19)
}

#test
{
    catch propagateTryBlockVoidFailure()
    @assert(@err != null)
    let err = cast(ErrValue) @err
    @assert(err.code == 21)
}

#test
{
    let value = trycatch propagateTrySuccess()
    @assert(value == 51)
    @assert(@err == null)
}

#test
{
    let value = trycatch inlineMayThrowValue(64)
    @assert(value == 64)
    @assert(@err == null)
}

#test
{
    let info = tryCatchFailureInfo()
    @assert(info.value == 0)
    @assert(!info.hasErr)
    @assert(info.code == 0)
}

#test
{
    let info = inlineTryCatchFailureInfo()
    @assert(info.value == 0)
    @assert(!info.hasErr)
    @assert(info.code == 0)
}

#test
{
    let value = assume mayThrowValue(77)
    @assert(value == 77)
    @assert(@err == null)
}

#test
{
    let info = assumeFailureInfo()
    @assert(info.value == 0)
    @assert(info.hasErr)
}

#test
{
    @assert(nestedTryHandled() == 23)
}

#test
{
    @assert(traceThrowCatch() == 124)
}
