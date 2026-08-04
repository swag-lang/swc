#global private

struct ErrValue
{
    using base: Swag.BaseError
    code:       s32 = 0
}

struct OtherErrValue
{
    using base: Swag.BaseError
    code:       s32 = 0
}

struct CatchInfo
{
    value:  s32
    hasErr: bool
    code:   s32
}

struct AggregateResult
{
    first:   s32 = 0
    second:  s32 = 0
    payload: [3] s32
}

struct AggregateInfo
{
    value:     AggregateResult
    hasErr:    bool
    code:      s32
    messageOk: bool
}

struct NullInfo
{
    isNull: bool
    hasErr: bool
    code:   s32
}

struct TraceInfo
{
    value:  s32
    hasErr: bool
    code:   s32
    trace:  s64
}

struct AggregateTraceInfo
{
    value:  AggregateResult
    hasErr: bool
    code:   s32
    trace:  s64
}

struct ErrCastInfo
{
    exactType:     bool
    baseType:      bool
    wrongType:     bool
    exactCastOk:   bool
    baseCastOk:    bool
    wrongCastNull: bool
    code:          s32
    messageOk:     bool
}

struct ErrNullCastInfo
{
    exactType:     bool
    baseType:      bool
    exactCastNull: bool
    baseCastNull:  bool
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

func mayFailValue(value: s32 = 42)->s32 fail
{
    return value
}

func mayFailVoid() fail {}

func alwaysFailValue(code: s32)->s32 fail
{
    fail ErrValue{code: code}
}

func alwaysFailVoid(code: s32) fail
{
    fail ErrValue{code: code}
}

func alwaysFailTypedVoid(code: s32) fail
{
    fail ErrValue{base: Swag.BaseError{"typed error"}, code: code}
}

func currentErrCode(err: #null any)->s32
{
    if err == null do
        return 0

    return (cast(ErrValue) err).code
}

#[Swag.Inline]
func inlineMayFailValue(value: s32)->s32 fail
{
    return value
}

#[Swag.Inline]
func inlineAlwaysFailValue(code: s32)->s32 fail
{
    fail ErrValue{code: code}
}

func propagateBareSuccess()->s32 fail
{
    return mayFailValue(42)
}

func propagateBareFailure()->s32 fail
{
    return alwaysFailValue(17)
}

func propagateTrySuccess()->s32 fail
{
    return try mayFailValue(51)
}

func propagateTryFailure()->s32 fail
{
    return try alwaysFailValue(18)
}

func propagateTryVoidSuccess() fail
{
    try mayFailVoid()
}

func propagateTryBlockVoidFailure() fail
{
    try
    {
        try alwaysFailVoid(21)
    }
}

func aggregateSuccess(seed: s32)->AggregateResult fail
{
    return AggregateResult{
        first: seed,
        second: seed + 1,
        payload: [seed + 2, seed + 3, seed + 4],
        }
}

func aggregateFailure(code: s32)->AggregateResult fail
{
    fail ErrValue{base: Swag.BaseError{"aggregate failure"}, code: code}
}

func nullablePointerFailure(code: s32)->#null *s32 fail
{
    fail ErrValue{code: code}
}

func nullableStringFailure(code: s32)->#null string fail
{
    fail ErrValue{code: code}
}

func nullableSliceFailure(code: s32)->#null [..] s32 fail
{
    fail ErrValue{code: code}
}

func chainTryLeaf()->s32 fail
{
    defer appendErrorTrace(1)
    return try alwaysFailValue(81)
}

func chainTryMid()->s32 fail
{
    defer appendErrorTrace(2)
    return try chainTryLeaf()
}

func chainTryTop()->s32 fail
{
    defer appendErrorTrace(4)
    return try chainTryMid()
}

func deferFailAfterReturn()->s32 fail
{
    defer appendErrorTrace(3)
    defer
    {
        appendErrorTrace(2)
        fail ErrValue{code: 82}
    }

    appendErrorTrace(1)
    return 99
}

func errDeferOverrideFailure()->s32 fail
{
    defer appendErrorTrace(3)
    defer #fail
    {
        appendErrorTrace(2)
        fail ErrValue{code: 84}
    }

    appendErrorTrace(1)
    fail ErrValue{code: 83}
}

func aggregateDeferFail()->AggregateResult fail
{
    defer
    {
        appendErrorTrace(2)
        fail ErrValue{code: 85}
    }

    appendErrorTrace(1)
    return AggregateResult{
        first: 10,
        second: 11,
        payload: [12, 13, 14],
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
    return catch inlineMayFailValue(63)
}

func catchFailureInfo()->CatchInfo
{
    var result: CatchInfo
    result.value  = catch propagateBareFailure() as err
    result.hasErr = err != null
    if err != null
    {
        let errv = cast(ErrValue) err
        result.code = errv.code
    }

    return result
}

func inlineCatchFailureInfo()->CatchInfo
{
    var result: CatchInfo
    result.value  = catch inlineAlwaysFailValue(41) as err2
    result.hasErr = err2 != null
    if err2 != null
    {
        let errv = cast(ErrValue) err2
        result.code = errv.code
    }

    return result
}

func catchTryFailureInfo()->CatchInfo
{
    var result: CatchInfo
    result.value  = catch propagateTryFailure() as err3
    result.hasErr = err3 != null
    if err3 != null
    {
        let errv = cast(ErrValue) err3
        result.code = errv.code
    }

    return result
}

func dismissFailureInfo()->CatchInfo
{
    var result: CatchInfo
    // 'catch' without a capture dismisses the error; the fallback is the type default.
    result.value  = catch propagateBareFailure()
    result.hasErr = false
    result.code   = 0
    return result
}

func inlineDismissSuccessValue()->s32
{
    return catch inlineMayFailValue(64)
}

func inlineDismissFailureInfo()->CatchInfo
{
    var result: CatchInfo
    // 'catch' without a capture dismisses the error; the fallback is the type default.
    result.value  = catch inlineAlwaysFailValue(42)
    result.hasErr = false
    result.code   = 0
    return result
}

func catchTryVoidSuccess()->bool
{
    catch propagateTryVoidSuccess() as err4
    return err4 == null
}

func catchTryBlockVoidFailureCode()->s32
{
    catch propagateTryBlockVoidFailure() as err5
    if err5 == null do
        return -1

    let errv = cast(ErrValue) err5
    return errv.code
}

func catchAggregateSuccess()->AggregateResult
{
    return catch aggregateSuccess(70)
}

func catchAggregateFailureInfo()->AggregateInfo
{
    var result: AggregateInfo
    result.value  = catch aggregateFailure(71) as err6
    result.hasErr = err6 != null
    if err6 != null
    {
        let errv = cast(ErrValue) err6
        result.code      = errv.code
        result.messageOk = errv.message == "aggregate failure"
    }

    return result
}

func dismissAggregateSuccess()->AggregateResult
{
    return catch aggregateSuccess(80)
}

func dismissAggregateFailureInfo()->AggregateInfo
{
    var result: AggregateInfo
    // 'catch' without a capture dismisses the error; the fallback is the type default.
    result.value  = catch aggregateFailure(72)
    result.hasErr = false
    result.code   = 0
    return result
}

func repeatedCatchFailureSum()->s32
{
    var result: s32 = 0
    for 40
    {
        catch alwaysFailVoid(cast(s32) @index + 1) as err7
        let err = cast(ErrValue) err7
        result += err.code
    }

    return result
}

func nestedTryHandled()->s32
{
    catch
    {
        try alwaysFailVoid(23)
    } as err

    if err == null do
        return -1

    let errv = cast(ErrValue) err
    return errv.code
}

#[Swag.Inline]
func traceFailLeaf() fail
{
    defer appendErrorTrace(1)
    fail ErrValue{code: 31}
}

#[Swag.Inline]
func traceFailMid() fail
{
    defer appendErrorTrace(2)
    traceFailLeaf()
}

#[Swag.Inline]
func traceFailTop() fail
{
    defer appendErrorTrace(4)
    traceFailMid()
}

func traceFailCatch()->s64
{
    resetErrorTrace()
    catch traceFailTop()
    return ErrorTrace
}

func catchNullablePointerFailureInfo()->NullInfo
{
    var result: NullInfo
    let value:  #null *s32 = catch nullablePointerFailure(73) as err
    result.isNull = value == null
    result.hasErr = err != null
    result.code   = currentErrCode(err)
    return result
}

func catchNullableStringFailureInfo()->NullInfo
{
    var result: NullInfo
    let value:  #null string = catch nullableStringFailure(74) as err
    result.isNull = value == null
    result.hasErr = err != null
    result.code   = currentErrCode(err)
    return result
}

func catchNullableSliceFailureInfo()->NullInfo
{
    var result: NullInfo
    let value:  #null [..] s32 = catch nullableSliceFailure(75) as err
    result.isNull = value == null
    result.hasErr = err != null
    result.code   = currentErrCode(err)
    return result
}

func dismissNullablePointerFailureInfo()->NullInfo
{
    var result: NullInfo
    let value:  #null *s32 = catch nullablePointerFailure(76)
    result.isNull = value == null
    result.hasErr = false
    result.code   = 0
    return result
}

func dismissNullableStringFailureInfo()->NullInfo
{
    var result: NullInfo
    let value:  #null string = catch nullableStringFailure(77)
    result.isNull = value == null
    result.hasErr = false
    result.code   = 0
    return result
}

func dismissNullableSliceFailureInfo()->NullInfo
{
    var result: NullInfo
    let value:  #null [..] s32 = catch nullableSliceFailure(78)
    result.isNull = value == null
    result.hasErr = false
    result.code   = 0
    return result
}

func chainedTryFailureInfo()->TraceInfo
{
    resetErrorTrace()

    var result: TraceInfo
    result.value  = catch chainTryTop() as err
    result.trace  = ErrorTrace
    result.hasErr = err != null
    result.code   = currentErrCode(err)
    return result
}

func deferFailAfterReturnInfo()->TraceInfo
{
    resetErrorTrace()

    var result: TraceInfo
    result.value  = catch deferFailAfterReturn() as err
    result.trace  = ErrorTrace
    result.hasErr = err != null
    result.code   = currentErrCode(err)
    return result
}

func errDeferOverrideFailureInfo()->TraceInfo
{
    resetErrorTrace()

    var result: TraceInfo
    result.value  = catch errDeferOverrideFailure() as err
    result.trace  = ErrorTrace
    result.hasErr = err != null
    result.code   = currentErrCode(err)
    return result
}

func dismissErrDeferOverrideFailureInfo()->TraceInfo
{
    resetErrorTrace()

    var result: TraceInfo
    result.value  = catch errDeferOverrideFailure()
    result.trace  = ErrorTrace
    result.hasErr = false
    result.code   = 0
    return result
}

func aggregateDeferFailInfo()->AggregateTraceInfo
{
    resetErrorTrace()

    var result: AggregateTraceInfo
    result.value  = catch aggregateDeferFail() as err
    result.trace  = ErrorTrace
    result.hasErr = err != null
    result.code   = currentErrCode(err)
    return result
}

func errIsAsFailureInfo()->ErrCastInfo
{
    var result: ErrCastInfo
    catch alwaysFailTypedVoid(86) as err8

    let exactErr = err8 as ErrValue
    let baseErr  = err8 as Swag.BaseError
    let otherErr = err8 as OtherErrValue

    result.exactType     = err8 is ErrValue
    result.baseType      = err8 is Swag.BaseError
    result.wrongType     = err8 is OtherErrValue
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
    catch mayFailVoid() as err9

    result.exactType     = err9 is ErrValue
    result.baseType      = err9 is Swag.BaseError
    result.exactCastNull = err9 as ErrValue == null
    result.baseCastNull  = err9 as Swag.BaseError == null
    return result
}

func expectSuccess()->s32
{
    return expect mayFailValue(77)
}

func notNullMaybePtr(p: *s32)->#null *s32 => p

func notNullPointerSuccess()->s32
{
    var storage: s32        = 91
    let maybe:   #null *s32 = notNullMaybePtr(&storage)
    let ptr                 = maybe!
    #assert(#typeof(ptr) == *s32)
    return dref ptr
}

func notNullSliceSuccess()->s32
{
    var values: [3] s32        = [4, 5, 6]
    let maybe:  #null [..] s32 = values
    let slice                  = maybe!
    #assert(#typeof(slice) == [..] s32)
    return slice[1] + cast(s32) @countof(slice)
}

func dismissSuccessValue()->s32
{
    return catch propagateTrySuccess()
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
    const V = #run errIsAsFailureInfo()
    #assert(V.exactType)
    #assert(V.baseType)
    #assert(!V.wrongType)
    #assert(V.exactCastOk)
    #assert(V.baseCastOk)
    #assert(V.wrongCastNull)
    #assert(V.code == 86)
    #assert(V.messageOk)
}

#test
{
    const V = #run errIsAsNullInfo()
    #assert(!V.exactType)
    #assert(!V.baseType)
    #assert(V.exactCastNull)
    #assert(V.baseCastNull)
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
    const V = #run dismissSuccessValue()
    #assert(V == 51)
}

#test
{
    const V = #run inlineDismissSuccessValue()
    #assert(V == 64)
}

#test
{
    const V = #run dismissAggregateSuccess()
    #assert(V.first == 80)
    #assert(V.second == 81)
    #assert(V.payload[0] == 82)
    #assert(V.payload[1] == 83)
    #assert(V.payload[2] == 84)
}

#test
{
    const V = #run dismissFailureInfo()
    #assert(V.value == 0)
    #assert(!V.hasErr)
    #assert(V.code == 0)
}

#test
{
    const V = #run dismissAggregateFailureInfo()
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
    const V = #run inlineDismissFailureInfo()
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
    const V = #run traceFailCatch()
    #assert(V == 124)
}

#test
{
    const V = #run catchNullablePointerFailureInfo()
    #assert(V.isNull)
    #assert(V.hasErr)
    #assert(V.code == 73)
}

#test
{
    const V = #run catchNullableStringFailureInfo()
    #assert(V.isNull)
    #assert(V.hasErr)
    #assert(V.code == 74)
}

#test
{
    const V = #run catchNullableSliceFailureInfo()
    #assert(V.isNull)
    #assert(V.hasErr)
    #assert(V.code == 75)
}

#test
{
    const V = #run dismissNullablePointerFailureInfo()
    #assert(V.isNull)
    #assert(!V.hasErr)
    #assert(V.code == 0)
}

#test
{
    const V = #run dismissNullableStringFailureInfo()
    #assert(V.isNull)
    #assert(!V.hasErr)
    #assert(V.code == 0)
}

#test
{
    const V = #run dismissNullableSliceFailureInfo()
    #assert(V.isNull)
    #assert(!V.hasErr)
    #assert(V.code == 0)
}

#test
{
    const V = #run chainedTryFailureInfo()
    #assert(V.value == 0)
    #assert(V.hasErr)
    #assert(V.code == 81)
    #assert(V.trace == 124)
}

#test
{
    const V = #run deferFailAfterReturnInfo()
    #assert(V.value == 0)
    #assert(V.hasErr)
    #assert(V.code == 82)
    #assert(V.trace == 123)
}

#test
{
    const V = #run errDeferOverrideFailureInfo()
    #assert(V.value == 0)
    #assert(V.hasErr)
    #assert(V.code == 84)
    #assert(V.trace == 123)
}

#test
{
    const V = #run dismissErrDeferOverrideFailureInfo()
    #assert(V.value == 0)
    #assert(!V.hasErr)
    #assert(V.code == 0)
    #assert(V.trace == 123)
}

#test
{
    const V = #run aggregateDeferFailInfo()
    #assert(V.value.first == 0)
    #assert(V.value.second == 0)
    #assert(V.value.payload[0] == 0)
    #assert(V.value.payload[1] == 0)
    #assert(V.value.payload[2] == 0)
    #assert(V.hasErr)
    #assert(V.code == 85)
    #assert(V.trace == 12)
}

#test
{
    const V = #run repeatedCatchFailureSum()
    #assert(V == 820)
}

#test
{
    const V = #run expectSuccess()
    #assert(V == 77)
}

#test
{
    const V = #run notNullPointerSuccess()
    #assert(V == 91)
}

#test
{
    const V = #run notNullSliceSuccess()
    #assert(V == 8)
}
