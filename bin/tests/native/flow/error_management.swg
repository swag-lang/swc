#global fileprivate

struct ErrValue
{
    using base: Swag.BaseError
    code: s32 = 0
}

struct OtherErrValue
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

struct NullInfo
{
    isNull: bool
    hasErr: bool
    code: s32
}

struct TraceInfo
{
    value: s32
    hasErr: bool
    code: s32
    trace: s64
}

struct AggregateTraceInfo
{
    value: AggregateResult
    hasErr: bool
    code: s32
    trace: s64
}

struct ErrCastInfo
{
    exactType: bool
    baseType: bool
    wrongType: bool
    exactCastOk: bool
    baseCastOk: bool
    wrongCastNull: bool
    code: s32
    messageOk: bool
}

struct ErrNullCastInfo
{
    exactType: bool
    baseType: bool
    exactCastNull: bool
    baseCastNull: bool
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

func alwaysThrowTypedVoid(code: s32) throw
{
    throw ErrValue{base: Swag.BaseError{"typed error"}, code: code}
}

func currentErrCode()->s32
{
    if @err == null do
        return 0

    let err = cast(ErrValue) @err
    return err.code
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

func nullablePointerFailure(code: s32)->#null *s32 throw
{
    throw ErrValue{code: code}
}

func nullableStringFailure(code: s32)->#null string throw
{
    throw ErrValue{code: code}
}

func nullableSliceFailure(code: s32)->#null [..] s32 throw
{
    throw ErrValue{code: code}
}

func chainTryLeaf()->s32 throw
{
    defer appendErrorTrace(1)
    return try alwaysThrowValue(81)
}

func chainTryMid()->s32 throw
{
    defer appendErrorTrace(2)
    return try chainTryLeaf()
}

func chainTryTop()->s32 throw
{
    defer appendErrorTrace(4)
    return try chainTryMid()
}

func deferThrowAfterReturn()->s32 throw
{
    defer appendErrorTrace(3)
    defer
    {
        appendErrorTrace(2)
        throw ErrValue{code: 82}
    }

    appendErrorTrace(1)
    return 99
}

func errDeferOverrideFailure()->s32 throw
{
    defer appendErrorTrace(3)
    defer #err
    {
        appendErrorTrace(2)
        throw ErrValue{code: 84}
    }

    appendErrorTrace(1)
    throw ErrValue{code: 83}
}

func aggregateDeferThrow()->AggregateResult throw
{
    defer
    {
        appendErrorTrace(2)
        throw ErrValue{code: 85}
    }

    appendErrorTrace(1)
    return AggregateResult{
        first: 10,
        second: 11,
        payload: [12, 13, 14],
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

func catchAggregateSuccess()->AggregateResult
{
    return catch aggregateSuccess(70)
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

func tryCatchAggregateSuccess()->AggregateResult
{
    return trycatch aggregateSuccess(80)
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

func recordAssumePanic(message: string, loc: SourceCodeLocation)
{
    let cxt = @getcontext()
    cxt.user0 += 1
    cxt.user1 = cast(u64) loc.lineStart
}

#[Swag.Safety(.Assume, true)]
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

#[Swag.Safety(.Assume, false)]
func assumeFailureNoSafety()->CatchInfo
{
    let cxt = @getcontext()
    cxt.user0 = 0
    cxt.user1 = 0
    cxt.panic = &recordAssumePanic
    defer cxt.panic = null

    var result: CatchInfo
    result.value = assume alwaysThrowValue(30)
    result.hasErr = cxt.user0 == 1
    result.code = cast(s32) cxt.user1
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

func catchNullablePointerFailureInfo()->NullInfo
{
    var result: NullInfo
    let value: #null *s32 = catch nullablePointerFailure(73)
    result.isNull = value == null
    result.hasErr = @err != null
    result.code   = currentErrCode()
    return result
}

func catchNullableStringFailureInfo()->NullInfo
{
    var result: NullInfo
    let value: #null string = catch nullableStringFailure(74)
    result.isNull = value == null
    result.hasErr = @err != null
    result.code   = currentErrCode()
    return result
}

func catchNullableSliceFailureInfo()->NullInfo
{
    var result: NullInfo
    let value: #null [..] s32 = catch nullableSliceFailure(75)
    result.isNull = value == null
    result.hasErr = @err != null
    result.code   = currentErrCode()
    return result
}

func tryCatchNullablePointerFailureInfo()->NullInfo
{
    var result: NullInfo
    let value: #null *s32 = trycatch nullablePointerFailure(76)
    result.isNull = value == null
    result.hasErr = @err != null
    result.code   = currentErrCode()
    return result
}

func tryCatchNullableStringFailureInfo()->NullInfo
{
    var result: NullInfo
    let value: #null string = trycatch nullableStringFailure(77)
    result.isNull = value == null
    result.hasErr = @err != null
    result.code   = currentErrCode()
    return result
}

func tryCatchNullableSliceFailureInfo()->NullInfo
{
    var result: NullInfo
    let value: #null [..] s32 = trycatch nullableSliceFailure(78)
    result.isNull = value == null
    result.hasErr = @err != null
    result.code   = currentErrCode()
    return result
}

func chainedTryFailureInfo()->TraceInfo
{
    resetErrorTrace()

    var result: TraceInfo
    result.value  = catch chainTryTop()
    result.trace  = ErrorTrace
    result.hasErr = @err != null
    result.code   = currentErrCode()
    return result
}

func deferThrowAfterReturnInfo()->TraceInfo
{
    resetErrorTrace()

    var result: TraceInfo
    result.value  = catch deferThrowAfterReturn()
    result.trace  = ErrorTrace
    result.hasErr = @err != null
    result.code   = currentErrCode()
    return result
}

func errDeferOverrideFailureInfo()->TraceInfo
{
    resetErrorTrace()

    var result: TraceInfo
    result.value  = catch errDeferOverrideFailure()
    result.trace  = ErrorTrace
    result.hasErr = @err != null
    result.code   = currentErrCode()
    return result
}

func tryCatchErrDeferOverrideFailureInfo()->TraceInfo
{
    resetErrorTrace()

    var result: TraceInfo
    result.value  = trycatch errDeferOverrideFailure()
    result.trace  = ErrorTrace
    result.hasErr = @err != null
    result.code   = currentErrCode()
    return result
}

func aggregateDeferThrowInfo()->AggregateTraceInfo
{
    resetErrorTrace()

    var result: AggregateTraceInfo
    result.value  = catch aggregateDeferThrow()
    result.trace  = ErrorTrace
    result.hasErr = @err != null
    result.code   = currentErrCode()
    return result
}

func errIsAsFailureInfo()->ErrCastInfo
{
    var result: ErrCastInfo
    catch alwaysThrowTypedVoid(86)

    let exactErr = @err as ErrValue
    let baseErr  = @err as Swag.BaseError
    let otherErr = @err as OtherErrValue

    result.exactType     = @err is ErrValue
    result.baseType      = @err is Swag.BaseError
    result.wrongType     = @err is OtherErrValue
    result.exactCastOk   = exactErr != null
    result.baseCastOk    = baseErr != null
    result.wrongCastNull = otherErr == null
    if exactErr != null do
        result.code = exactErr.code
    if baseErr != null do
        result.messageOk = baseErr.message == "typed error"
    return result
}

func errIsAsNullInfo()->ErrNullCastInfo
{
    var result: ErrNullCastInfo
    catch mayThrowVoid()

    result.exactType    = @err is ErrValue
    result.baseType     = @err is Swag.BaseError
    result.exactCastNull = @err as ErrValue == null
    result.baseCastNull  = @err as Swag.BaseError == null
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
    let info = errIsAsFailureInfo()
    @assert(info.exactType)
    @assert(info.baseType)
    @assert(!info.wrongType)
    @assert(info.exactCastOk)
    @assert(info.baseCastOk)
    @assert(info.wrongCastNull)
    @assert(info.code == 86)
    @assert(info.messageOk)
}

#test
{
    let info = errIsAsNullInfo()
    @assert(!info.exactType)
    @assert(!info.baseType)
    @assert(info.exactCastNull)
    @assert(info.baseCastNull)
}

#test
{
    let value = catchAggregateSuccess()
    @assert(value.first == 70)
    @assert(value.second == 71)
    @assert(value.payload[0] == 72)
    @assert(value.payload[1] == 73)
    @assert(value.payload[2] == 74)
    @assert(@err == null)
}

#test
{
    let info = catchAggregateFailureInfo()
    @assert(info.value.first == 0)
    @assert(info.value.second == 0)
    @assert(info.value.payload[0] == 0)
    @assert(info.value.payload[1] == 0)
    @assert(info.value.payload[2] == 0)
    @assert(info.hasErr)
    @assert(info.code == 71)
    @assert(info.messageOk)
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
    let value = trycatch aggregateSuccess(80)
    @assert(value.first == 80)
    @assert(value.second == 81)
    @assert(value.payload[0] == 82)
    @assert(value.payload[1] == 83)
    @assert(value.payload[2] == 84)
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
    let info = tryCatchAggregateFailureInfo()
    @assert(info.value.first == 0)
    @assert(info.value.second == 0)
    @assert(info.value.payload[0] == 0)
    @assert(info.value.payload[1] == 0)
    @assert(info.value.payload[2] == 0)
    @assert(!info.hasErr)
    @assert(info.code == 0)
    @assert(!info.messageOk)
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
    @assert(@err == null)
}

#test
{
    let info = assumeFailureNoSafety()
    @assert(info.value == 0)
    @assert(!info.hasErr)
    @assert(info.code == 0)
    @assert(@err == null)
}

#test
{
    @assert(nestedTryHandled() == 23)
}

#test
{
    @assert(traceThrowCatch() == 124)
}

#test
{
    let info = catchNullablePointerFailureInfo()
    @assert(info.isNull)
    @assert(info.hasErr)
    @assert(info.code == 73)
}

#test
{
    let info = catchNullableStringFailureInfo()
    @assert(info.isNull)
    @assert(info.hasErr)
    @assert(info.code == 74)
}

#test
{
    let info = catchNullableSliceFailureInfo()
    @assert(info.isNull)
    @assert(info.hasErr)
    @assert(info.code == 75)
}

#test
{
    let info = tryCatchNullablePointerFailureInfo()
    @assert(info.isNull)
    @assert(!info.hasErr)
    @assert(info.code == 0)
}

#test
{
    let info = tryCatchNullableStringFailureInfo()
    @assert(info.isNull)
    @assert(!info.hasErr)
    @assert(info.code == 0)
}

#test
{
    let info = tryCatchNullableSliceFailureInfo()
    @assert(info.isNull)
    @assert(!info.hasErr)
    @assert(info.code == 0)
}

#test
{
    let info = chainedTryFailureInfo()
    @assert(info.value == 0)
    @assert(info.hasErr)
    @assert(info.code == 81)
    @assert(info.trace == 124)
}

#test
{
    let info = deferThrowAfterReturnInfo()
    @assert(info.value == 0)
    @assert(info.hasErr)
    @assert(info.code == 82)
    @assert(info.trace == 123)
}

#test
{
    let info = errDeferOverrideFailureInfo()
    @assert(info.value == 0)
    @assert(info.hasErr)
    @assert(info.code == 84)
    @assert(info.trace == 123)
}

#test
{
    let info = tryCatchErrDeferOverrideFailureInfo()
    @assert(info.value == 0)
    @assert(!info.hasErr)
    @assert(info.code == 0)
    @assert(info.trace == 123)
}

#test
{
    let info = aggregateDeferThrowInfo()
    @assert(info.value.first == 0)
    @assert(info.value.second == 0)
    @assert(info.value.payload[0] == 0)
    @assert(info.value.payload[1] == 0)
    @assert(info.value.payload[2] == 0)
    @assert(info.hasErr)
    @assert(info.code == 85)
    @assert(info.trace == 12)
}

#test
{
    @assert(repeatedCatchFailureSum() == 820)
}
