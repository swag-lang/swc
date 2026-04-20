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

struct AggregateResult
{
    first: s32 = 0
    second: s32 = 0
    payload: [3] s32
}

struct AggregateInfo
{
    value: AggregateResult
    hasErr: bool
    code: s32
    messageOk: bool
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

func aggregateSuccess(seed: s32)->AggregateResult throw
{
    return AggregateResult{
        first: seed,
        second: seed + 1,
        payload: [seed + 2, seed + 3, seed + 4],
    }
}

func aggregateFailure(code: s32)->AggregateResult throw
{
    throw ErrValue{base: Swag.BaseError{"aggregate failure"}, code: code}
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

func catchAggregateSuccess()->AggregateResult
{
    return catch aggregateSuccess(70)
}

func catchAggregateFailureInfo()->AggregateInfo
{
    var result: AggregateInfo
    result.value = catch aggregateFailure(71)
    result.hasErr = @err != null
    if @err != null
    {
        let err = cast(ErrValue) @err
        result.code = err.code
        result.messageOk = err.message == "aggregate failure"
    }

    return result
}

func tryCatchAggregateSuccess()->AggregateResult
{
    return trycatch aggregateSuccess(80)
}

func tryCatchAggregateFailureInfo()->AggregateInfo
{
    var result: AggregateInfo
    result.value = trycatch aggregateFailure(72)
    result.hasErr = @err != null
    if @err != null
    {
        let err = cast(ErrValue) @err
        result.code = err.code
        result.messageOk = err.message == "aggregate failure"
    }

    return result
}

func repeatedCatchFailureSum()->s32
{
    var result: s32 = 0
    for 40
    {
        catch alwaysThrowVoid(cast(s32) @index + 1)
        let err = cast(ErrValue) @err
        result += err.code
    }

    return result
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
    const V = #run catchAggregateSuccess()
    #assert(V.first == 70)
    #assert(V.second == 71)
    #assert(V.payload[0] == 72)
    #assert(V.payload[1] == 73)
    #assert(V.payload[2] == 74)
}

#test
{
    const V = #run catchAggregateFailureInfo()
    #assert(V.value.first == 0)
    #assert(V.value.second == 0)
    #assert(V.value.payload[0] == 0)
    #assert(V.value.payload[1] == 0)
    #assert(V.value.payload[2] == 0)
    #assert(V.hasErr)
    #assert(V.code == 71)
    #assert(V.messageOk)
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
    const V = #run tryCatchAggregateSuccess()
    #assert(V.first == 80)
    #assert(V.second == 81)
    #assert(V.payload[0] == 82)
    #assert(V.payload[1] == 83)
    #assert(V.payload[2] == 84)
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
    const V = #run tryCatchAggregateFailureInfo()
    #assert(V.value.first == 0)
    #assert(V.value.second == 0)
    #assert(V.value.payload[0] == 0)
    #assert(V.value.payload[1] == 0)
    #assert(V.value.payload[2] == 0)
    #assert(!V.hasErr)
    #assert(V.code == 0)
    #assert(!V.messageOk)
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
    const V = #run repeatedCatchFailureSum()
    #assert(V == 820)
}

#test
{
    const V = #run assumeSuccess()
    #assert(V == 77)
}
