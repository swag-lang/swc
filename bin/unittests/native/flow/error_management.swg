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

func propagateBareVoidFailure() fail
{
    alwaysFailVoid(19)
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
        payload: [12, 13, 14]
        }
}

func nestedTryHandled()->s32
{
    catch
    {
        try alwaysFailVoid(23)
    } as err

    if err == null do
        return -1

    return (cast(ErrValue) err).code
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

func catchAggregateSuccess()->AggregateResult
{
    return catch aggregateSuccess(70)
}

func inlineCatchFailureInfo()->CatchInfo
{
    var result: CatchInfo
    result.value  = catch inlineAlwaysFailValue(41) as err
    result.hasErr = err != null
    if err != null
    {
        let ev = cast(ErrValue) err
        result.code = ev.code
    }

    return result
}

func catchFailureInfo()->CatchInfo
{
    var result: CatchInfo
    result.value  = catch propagateBareFailure() as err2
    result.hasErr = err2 != null
    if err2 != null
    {
        let ev = cast(ErrValue) err2
        result.code = ev.code
    }

    return result
}

func catchAggregateFailureInfo()->AggregateInfo
{
    var result: AggregateInfo
    result.value  = catch aggregateFailure(71) as err3
    result.hasErr = err3 != null
    if err3 != null
    {
        let ev = cast(ErrValue) err3
        result.code      = ev.code
        result.messageOk = ev.message == "aggregate failure"
    }

    return result
}

func catchTryFailureInfo()->CatchInfo
{
    var result: CatchInfo
    result.value  = catch propagateTryFailure() as err4
    result.hasErr = err4 != null
    if err4 != null
    {
        let ev = cast(ErrValue) err4
        result.code = ev.code
    }

    return result
}

func catchStrictEnumFailureInfo()->bool
{
    let value = catch alwaysFailStrictEnum(87) as err5
    return value == cast(FailStrictEnumAlias) FailStrictEnum.Zero and err5 != null and currentErrCode(err5) == 87
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
    result.value  = catch propagateBareFailure()
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

func recordExpectPanic(message: #null string, loc: SourceCodeLocation)
{
    let cxt = @getcontext()
    cxt.user0 += 1
    cxt.user1 = cast(u64) loc.lineStart
}

#[Swag.Safety(.Expect, true)]
func expectFailureInfo()->CatchInfo
{
    let cxt = @getcontext()
    cxt.user0 = 0
    cxt.user1 = 0
    cxt.panic = &recordExpectPanic
    defer cxt.panic = null

    var result: CatchInfo
    result.value  = expect alwaysFailValue(29)
    result.hasErr = cxt.user0 == 1
    result.code   = cast(s32) cxt.user1
    return result
}

#[Swag.Safety(.Expect, false)]
func expectFailureNoSafety()->CatchInfo
{
    let cxt = @getcontext()
    cxt.user0 = 0
    cxt.user1 = 0
    cxt.panic = &recordExpectPanic
    defer cxt.panic = null

    var result: CatchInfo
    result.value  = expect alwaysFailValue(30)
    result.hasErr = cxt.user0 == 1
    result.code   = cast(s32) cxt.user1
    return result
}

func repeatedCatchFailureSum()->s32
{
    var result: s32 = 0
    for 40
    {
        catch alwaysFailVoid(cast(s32) @index + 1) as err6
        let err = cast(ErrValue) err6
        result += err.code
    }

    return result
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
    catch alwaysFailTypedVoid(86) as err7

    let exactErr = err7 as ErrValue
    let baseErr  = err7 as Swag.BaseError
    let otherErr = err7 as OtherErrValue

    result.exactType     = err7 is ErrValue
    result.baseType      = err7 is Swag.BaseError
    result.wrongType     = err7 is OtherErrValue
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
    catch mayFailVoid() as err8

    result.exactType     = err8 is ErrValue
    result.baseType      = err8 is Swag.BaseError
    result.exactCastNull = err8 as ErrValue == null
    result.baseCastNull  = err8 as Swag.BaseError == null
    return result
}

func notNullMaybePtr(p: *s32)->#null *s32 => p

func notNullPointerSuccess()->s32
{
    var storage: s32        = 91
    let maybe:   #null *s32 = notNullMaybePtr(&storage)
    let ptr                 = maybe!
    #assert(#typeof(ptr) == *s32)
    return ptr[]
}

func notNullSliceSuccess()->s32
{
    var values: [3] s32        = [4, 5, 6]
    let maybe:  #null [..] s32 = values
    let slice                  = maybe!
    #assert(#typeof(slice) == [..] s32)
    return slice[1] + cast(s32) @countof(slice)
}

#test
{
    let value = catch propagateBareSuccess() as err
    @assert(value == 42)
    @assert(err == null)
}

#test
{
    let value = catch propagateTrySuccess() as err
    @assert(value == 51)
    @assert(err == null)
}

#test
{
    let value = catch inlineMayFailValue(63) as err
    @assert(value == 63)
    @assert(err == null)
}

#test
{
    catch propagateTryVoidSuccess() as err9
    @assert(err9 == null)
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
    @assert(catchStrictEnumFailureInfo())
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
    catch propagateBareVoidFailure() as err10
    @assert(err10 != null)
    let err = cast(ErrValue) err10
    @assert(err.code == 19)
}

#test
{
    catch propagateTryBlockVoidFailure() as err11
    @assert(err11 != null)
    let err = cast(ErrValue) err11
    @assert(err.code == 21)
}

#test
{
    let value = catch propagateTrySuccess() as err
    @assert(value == 51)
    @assert(err == null)
}

#test
{
    let value = catch inlineMayFailValue(64) as err
    @assert(value == 64)
    @assert(err == null)
}

#test
{
    let value = catch aggregateSuccess(80)
    @assert(value.first == 80)
    @assert(value.second == 81)
    @assert(value.payload[0] == 82)
    @assert(value.payload[1] == 83)
    @assert(value.payload[2] == 84)
}

#test
{
    let info = dismissFailureInfo()
    @assert(info.value == 0)
    @assert(!info.hasErr)
    @assert(info.code == 0)
}

#test
{
    let info = inlineDismissFailureInfo()
    @assert(info.value == 0)
    @assert(!info.hasErr)
    @assert(info.code == 0)
}

#test
{
    let info = dismissAggregateFailureInfo()
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
    let value = expect mayFailValue(77)
    @assert(value == 77)
}

#test
{
    @assert(notNullPointerSuccess() == 91)
}

#test
{
    @assert(notNullSliceSuccess() == 8)
}

#test
{
    let info = expectFailureInfo()
    @assert(info.value == 0)
    @assert(info.hasErr)
}

#test
{
    let info = expectFailureNoSafety()
    @assert(info.value == 0)
    @assert(!info.hasErr)
    @assert(info.code == 0)
}

#test
{
    @assert(nestedTryHandled() == 23)
}

#test
{
    @assert(traceFailCatch() == 124)
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
    let info = dismissNullablePointerFailureInfo()
    @assert(info.isNull)
    @assert(!info.hasErr)
    @assert(info.code == 0)
}

#test
{
    let info = dismissNullableStringFailureInfo()
    @assert(info.isNull)
    @assert(!info.hasErr)
    @assert(info.code == 0)
}

#test
{
    let info = dismissNullableSliceFailureInfo()
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
    let info = deferFailAfterReturnInfo()
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
    let info = dismissErrDeferOverrideFailureInfo()
    @assert(info.value == 0)
    @assert(!info.hasErr)
    @assert(info.code == 0)
    @assert(info.trace == 123)
}

#test
{
    let info = aggregateDeferFailInfo()
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

#test
{
    try tryIfElse(false)
    @assert(ErrorTrace == 1)

    try tryIfElse(true)
    @assert(ErrorTrace == 0)
}
