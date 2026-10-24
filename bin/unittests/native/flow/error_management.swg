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

enum FailStrictEnum: u32
{
    Zero = 0,
    One  = 1
}

#[Swag.Strict]
alias FailStrictEnumAlias = FailStrictEnum

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

func tryIfElse(condition: bool) fail
{
    resetErrorTrace()
    if condition do
        try mayFailVoid()
    else do
        appendErrorTrace(1)
}

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

func alwaysFailStrictEnum(code: s32)->FailStrictEnumAlias fail
{
    fail ErrValue{code: code}
}

func currentErrCode(err: any?)->s32
{
    if err == null do
        return 0

    return assume cast (ErrValue, err).code
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

func propagateExplicitSuccess()->s32 fail
{
    return try mayFailValue(42)
}

func propagateExplicitFailure()->s32 fail
{
    return try alwaysFailValue(17)
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

func propagateExplicitVoidFailure() fail
{
    try alwaysFailVoid(19)
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
        payload: [seed + 2, seed + 3, seed + 4]
        }
}

func aggregateFailure(code: s32)->AggregateResult fail
{
    fail ErrValue{base: Swag.BaseError{"aggregate failure"}, code: code}
}

func nullablePointerFailure(code: s32)->*s32? fail
{
    fail ErrValue{code: code}
}

func nullableStringFailure(code: s32)->string? fail
{
    fail ErrValue{code: code}
}

func nullableSliceFailure(code: s32)->[..] s32? fail
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
        payload: [12, 13, 14]
        }
}

func nestedTryHandled()->s32
{
    var errOutcome: Swag.Error
    catch {
        try alwaysFailVoid(23)
    } as errOutcome
    let err = errOutcome.value()

    if err == null do
        return -1

    return assume cast (ErrValue, err).code
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
    try traceFailLeaf()
}

#[Swag.Inline]
func traceFailTop() fail
{
    defer appendErrorTrace(4)
    try traceFailMid()
}

func traceFailCatch()->s64
{
    resetErrorTrace()
    catch traceFailTop()
    return ErrorTrace
}

func catchAggregateSuccess()->AggregateResult
{
    return catch aggregateSuccess(70)
}

func inlineCatchFailureInfo()->CatchInfo
{
    var result:     CatchInfo
    var errOutcome: Swag.Error
    catch { result.value = try inlineAlwaysFailValue(41) } as errOutcome
    let err = errOutcome.value()
    result.hasErr = err != null
    if err != null
    {
        let ev = assume cast (ErrValue, err)
        result.code = ev.code
    }

    return result
}

func catchFailureInfo()->CatchInfo
{
    var result:      CatchInfo
    var err2Outcome: Swag.Error
    catch { result.value = try propagateExplicitFailure() } as err2Outcome
    let err2 = err2Outcome.value()
    result.hasErr = err2 != null
    if err2 != null
    {
        let ev = assume cast (ErrValue, err2)
        result.code = ev.code
    }

    return result
}

func catchAggregateFailureInfo()->AggregateInfo
{
    var result:      AggregateInfo
    var err3Outcome: Swag.Error
    catch { result.value = try aggregateFailure(71) } as err3Outcome
    let err3 = err3Outcome.value()
    result.hasErr = err3 != null
    if err3 != null
    {
        let ev = assume cast (ErrValue, err3)
        result.code      = ev.code
        result.messageOk = ev.message == "aggregate failure"
    }

    return result
}

func catchTryFailureInfo()->CatchInfo
{
    var result:      CatchInfo
    var err4Outcome: Swag.Error
    catch { result.value = try propagateTryFailure() } as err4Outcome
    let err4 = err4Outcome.value()
    result.hasErr = err4 != null
    if err4 != null
    {
        let ev = assume cast (ErrValue, err4)
        result.code = ev.code
    }

    return result
}

func catchStrictEnumFailureInfo()->bool
{
    var err5Outcome: Swag.Error
    let value = catch alwaysFailStrictEnum(87) as err5Outcome orelse cast(FailStrictEnumAlias, FailStrictEnum.Zero)
    let err5  = err5Outcome.value()
    return value == cast(FailStrictEnumAlias, FailStrictEnum.Zero) and
           err5 != null and
           currentErrCode(err5) == 87
}

func dismissAggregateSuccess()->AggregateResult
{
    return catch aggregateSuccess(80)
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

func dismissFailureInfo()->CatchInfo
{
    var result: CatchInfo
    // 'catch' without a capture dismisses the error; the fallback is the type default.
    result.value  = catch propagateExplicitFailure()
    result.hasErr = false
    result.code   = 0
    return result
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
    for index in 40
    {
        var err6Outcome: Swag.Error
        catch alwaysFailVoid(cast(s32, index) + 1) as err6Outcome
        let err6 = err6Outcome.value()
        let err  = assume cast (ErrValue, err6)
        result += err.code
    }

    return result
}

func catchNullablePointerFailureInfo()->NullInfo
{
    var result:     NullInfo
    var errOutcome: Swag.Error
    var value:      *s32?
    catch { value = try nullablePointerFailure(73) } as errOutcome
    let err = errOutcome.value()
    result.isNull = value == null
    result.hasErr = err != null
    result.code   = currentErrCode(err)
    return result
}

func catchNullableStringFailureInfo()->NullInfo
{
    var result:     NullInfo
    var errOutcome: Swag.Error
    var value:      string?
    catch { value = try nullableStringFailure(74) } as errOutcome
    let err = errOutcome.value()
    result.isNull = value == null
    result.hasErr = err != null
    result.code   = currentErrCode(err)
    return result
}

func catchNullableSliceFailureInfo()->NullInfo
{
    var result:     NullInfo
    var errOutcome: Swag.Error
    var value:      [..] s32?
    catch { value = try nullableSliceFailure(75) } as errOutcome
    let err = errOutcome.value()
    result.isNull = value == null
    result.hasErr = err != null
    result.code   = currentErrCode(err)
    return result
}

func dismissNullablePointerFailureInfo()->NullInfo
{
    var result: NullInfo
    let value:  *s32? = catch nullablePointerFailure(76)
    result.isNull = value == null
    result.hasErr = false
    result.code   = 0
    return result
}

func dismissNullableStringFailureInfo()->NullInfo
{
    var result: NullInfo
    let value:  string? = catch nullableStringFailure(77)
    result.isNull = value == null
    result.hasErr = false
    result.code   = 0
    return result
}

func dismissNullableSliceFailureInfo()->NullInfo
{
    var result: NullInfo
    let value:  [..] s32? = catch nullableSliceFailure(78)
    result.isNull = value == null
    result.hasErr = false
    result.code   = 0
    return result
}

func chainedTryFailureInfo()->TraceInfo
{
    resetErrorTrace()

    var result:     TraceInfo
    var errOutcome: Swag.Error
    catch { result.value = try chainTryTop() } as errOutcome
    let err = errOutcome.value()
    result.trace  = ErrorTrace
    result.hasErr = err != null
    result.code   = currentErrCode(err)
    return result
}

func deferFailAfterReturnInfo()->TraceInfo
{
    resetErrorTrace()

    var result:     TraceInfo
    var errOutcome: Swag.Error
    catch { result.value = try deferFailAfterReturn() } as errOutcome
    let err = errOutcome.value()
    result.trace  = ErrorTrace
    result.hasErr = err != null
    result.code   = currentErrCode(err)
    return result
}

func errDeferOverrideFailureInfo()->TraceInfo
{
    resetErrorTrace()

    var result:     TraceInfo
    var errOutcome: Swag.Error
    catch { result.value = try errDeferOverrideFailure() } as errOutcome
    let err = errOutcome.value()
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

    var result:     AggregateTraceInfo
    var errOutcome: Swag.Error
    catch { result.value = try aggregateDeferFail() } as errOutcome
    let err = errOutcome.value()
    result.trace  = ErrorTrace
    result.hasErr = err != null
    result.code   = currentErrCode(err)
    return result
}

func errIsAsFailureInfo()->ErrCastInfo
{
    var result:      ErrCastInfo
    var err7Outcome: Swag.Error
    catch alwaysFailTypedVoid(86) as err7Outcome
    let err7 = err7Outcome.value()

    let exactErr = catch cast(*ErrValue?, err7)
    let baseErr  = catch cast(*Swag.BaseError?, err7)
    let otherErr = catch cast(*OtherErrValue?, err7)

    result.exactType     = (err7 is ErrValue)
    result.baseType      = (err7 is Swag.BaseError)
    result.wrongType     = (err7 is OtherErrValue)
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
    var result:      ErrNullCastInfo
    var err8Outcome: Swag.Error
    catch mayFailVoid() as err8Outcome
    let err8 = err8Outcome.value()

    result.exactType     = (err8 is ErrValue)
    result.baseType      = (err8 is Swag.BaseError)
    result.exactCastNull = not (err8 is ErrValue)
    result.baseCastNull  = not (err8 is Swag.BaseError)
    return result
}

func notNullMaybePtr(p: *s32)->*s32? => p

func notNullPointerSuccess()->s32
{
    var storage: s32   = 91
    let maybe:   *s32? = notNullMaybePtr(&storage)
    let ptr = maybe!
    #assert(#typeof(ptr) == *s32)
    return ptr[]
}

func notNullSliceSuccess()->s32
{
    var values: [3] s32   = [4, 5, 6]
    let maybe:  [..] s32? = values
    let slice = maybe!
    #assert(#typeof(slice) == [..] s32)
    return slice[1] + cast(s32, slice.count)
}

#test
{
    var errOutcome: Swag.Error
    var value:      #decltype(expect propagateExplicitSuccess())
    catch { value = try propagateExplicitSuccess() } as errOutcome
    let err = errOutcome.value()
    Swag.assert(value == 42)
    Swag.assert(err == null)
}

#test
{
    var errOutcome: Swag.Error
    var value:      #decltype(expect propagateTrySuccess())
    catch { value = try propagateTrySuccess() } as errOutcome
    let err = errOutcome.value()
    Swag.assert(value == 51)
    Swag.assert(err == null)
}

#test
{
    var errOutcome: Swag.Error
    var value:      #decltype(expect inlineMayFailValue(63))
    catch { value = try inlineMayFailValue(63) } as errOutcome
    let err = errOutcome.value()
    Swag.assert(value == 63)
    Swag.assert(err == null)
}

#test
{
    var err9Outcome: Swag.Error
    catch propagateTryVoidSuccess() as err9Outcome
    let err9 = err9Outcome.value()
    Swag.assert(err9 == null)
}

#test
{
    let info = catchFailureInfo()
    Swag.assert(info.value == 0)
    Swag.assert(info.hasErr)
    Swag.assert(info.code == 17)
}

#test
{
    let info = inlineCatchFailureInfo()
    Swag.assert(info.value == 0)
    Swag.assert(info.hasErr)
    Swag.assert(info.code == 41)
}

#test
{
    let info = catchTryFailureInfo()
    Swag.assert(info.value == 0)
    Swag.assert(info.hasErr)
    Swag.assert(info.code == 18)
}

#test
{
    Swag.assert(catchStrictEnumFailureInfo())
}

#test
{
    let info = errIsAsFailureInfo()
    Swag.assert(info.exactType)
    Swag.assert(info.baseType)
    Swag.assert(not info.wrongType)
    Swag.assert(info.exactCastOk)
    Swag.assert(info.baseCastOk)
    Swag.assert(info.wrongCastNull)
    Swag.assert(info.code == 86)
    Swag.assert(info.messageOk)
}

#test
{
    let info = errIsAsNullInfo()
    Swag.assert(not info.exactType)
    Swag.assert(not info.baseType)
    Swag.assert(info.exactCastNull)
    Swag.assert(info.baseCastNull)
}

#test
{
    let value = catchAggregateSuccess()
    Swag.assert(value.first == 70)
    Swag.assert(value.second == 71)
    Swag.assert(value.payload[0] == 72)
    Swag.assert(value.payload[1] == 73)
    Swag.assert(value.payload[2] == 74)
}

#test
{
    let info = catchAggregateFailureInfo()
    Swag.assert(info.value.first == 0)
    Swag.assert(info.value.second == 0)
    Swag.assert(info.value.payload[0] == 0)
    Swag.assert(info.value.payload[1] == 0)
    Swag.assert(info.value.payload[2] == 0)
    Swag.assert(info.hasErr)
    Swag.assert(info.code == 71)
    Swag.assert(info.messageOk)
}

#test
{
    var err10Outcome: Swag.Error
    catch propagateExplicitVoidFailure() as err10Outcome
    let err10 = err10Outcome.value()
    Swag.assert(err10 != null)
    let err = assume cast (ErrValue, err10)
    Swag.assert(err.code == 19)
}

#test
{
    var err11Outcome: Swag.Error
    catch propagateTryBlockVoidFailure() as err11Outcome
    let err11 = err11Outcome.value()
    Swag.assert(err11 != null)
    let err = assume cast (ErrValue, err11)
    Swag.assert(err.code == 21)
}

#test
{
    var errOutcome: Swag.Error
    var value:      #decltype(expect propagateTrySuccess())
    catch { value = try propagateTrySuccess() } as errOutcome
    let err = errOutcome.value()
    Swag.assert(value == 51)
    Swag.assert(err == null)
}

#test
{
    var errOutcome: Swag.Error
    var value:      #decltype(expect inlineMayFailValue(64))
    catch { value = try inlineMayFailValue(64) } as errOutcome
    let err = errOutcome.value()
    Swag.assert(value == 64)
    Swag.assert(err == null)
}

#test
{
    let value = catch aggregateSuccess(80)
    Swag.assert(value.first == 80)
    Swag.assert(value.second == 81)
    Swag.assert(value.payload[0] == 82)
    Swag.assert(value.payload[1] == 83)
    Swag.assert(value.payload[2] == 84)
}

#test
{
    let info = dismissFailureInfo()
    Swag.assert(info.value == 0)
    Swag.assert(not info.hasErr)
    Swag.assert(info.code == 0)
}

#test
{
    let info = inlineDismissFailureInfo()
    Swag.assert(info.value == 0)
    Swag.assert(not info.hasErr)
    Swag.assert(info.code == 0)
}

#test
{
    let info = dismissAggregateFailureInfo()
    Swag.assert(info.value.first == 0)
    Swag.assert(info.value.second == 0)
    Swag.assert(info.value.payload[0] == 0)
    Swag.assert(info.value.payload[1] == 0)
    Swag.assert(info.value.payload[2] == 0)
    Swag.assert(not info.hasErr)
    Swag.assert(info.code == 0)
    Swag.assert(not info.messageOk)
}

#test
{
    let value = expect mayFailValue(77)
    Swag.assert(value == 77)
}

#test
{
    Swag.assert(notNullPointerSuccess() == 91)
}

#test
{
    Swag.assert(notNullSliceSuccess() == 8)
}

#test
{
    Swag.assert(nestedTryHandled() == 23)
}

#test
{
    Swag.assert(traceFailCatch() == 124)
}

#test
{
    let info = catchNullablePointerFailureInfo()
    Swag.assert(info.isNull)
    Swag.assert(info.hasErr)
    Swag.assert(info.code == 73)
}

#test
{
    let info = catchNullableStringFailureInfo()
    Swag.assert(info.isNull)
    Swag.assert(info.hasErr)
    Swag.assert(info.code == 74)
}

#test
{
    let info = catchNullableSliceFailureInfo()
    Swag.assert(info.isNull)
    Swag.assert(info.hasErr)
    Swag.assert(info.code == 75)
}

#test
{
    let info = dismissNullablePointerFailureInfo()
    Swag.assert(info.isNull)
    Swag.assert(not info.hasErr)
    Swag.assert(info.code == 0)
}

#test
{
    let info = dismissNullableStringFailureInfo()
    Swag.assert(info.isNull)
    Swag.assert(not info.hasErr)
    Swag.assert(info.code == 0)
}

#test
{
    let info = dismissNullableSliceFailureInfo()
    Swag.assert(info.isNull)
    Swag.assert(not info.hasErr)
    Swag.assert(info.code == 0)
}

#test
{
    let info = chainedTryFailureInfo()
    Swag.assert(info.value == 0)
    Swag.assert(info.hasErr)
    Swag.assert(info.code == 81)
    Swag.assert(info.trace == 124)
}

#test
{
    let info = deferFailAfterReturnInfo()
    Swag.assert(info.value == 0)
    Swag.assert(info.hasErr)
    Swag.assert(info.code == 82)
    Swag.assert(info.trace == 123)
}

#test
{
    let info = errDeferOverrideFailureInfo()
    Swag.assert(info.value == 0)
    Swag.assert(info.hasErr)
    Swag.assert(info.code == 84)
    Swag.assert(info.trace == 123)
}

#test
{
    let info = dismissErrDeferOverrideFailureInfo()
    Swag.assert(info.value == 0)
    Swag.assert(not info.hasErr)
    Swag.assert(info.code == 0)
    Swag.assert(info.trace == 123)
}

#test
{
    let info = aggregateDeferFailInfo()
    Swag.assert(info.value.first == 0)
    Swag.assert(info.value.second == 0)
    Swag.assert(info.value.payload[0] == 0)
    Swag.assert(info.value.payload[1] == 0)
    Swag.assert(info.value.payload[2] == 0)
    Swag.assert(info.hasErr)
    Swag.assert(info.code == 85)
    Swag.assert(info.trace == 12)
}

#test
{
    Swag.assert(repeatedCatchFailureSum() == 820)
}

#test
{
    expect tryIfElse(false)
    Swag.assert(ErrorTrace == 1)

    expect tryIfElse(true)
    Swag.assert(ErrorTrace == 0)
}
