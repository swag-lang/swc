#global fileprivate

var gClonePayloadOpCastCalls: s32 = 0
var gClonePayloadOpSetCalls: s32 = 0

struct ClonePayloadCastBox
{
    value: s32
}

impl ClonePayloadCastBox
{
    #[Swag.Implicit, Swag.NoInline]
    mtd const opCast() -> s32
    {
        gClonePayloadOpCastCalls += 1
        return .value + 1
    }
}

struct ClonePayloadSetTarget
{
    value: s32
    calls: s32
    sentinel: s32 = 77
}

impl ClonePayloadSetTarget
{
    #[Swag.NoInline]
    mtd opSet(value: s32)
    {
        gClonePayloadOpSetCalls += 1
        .value = value + 2
        .calls += 1
    }
}

func(T) genericClonePayloadOpCastBody(box: ClonePayloadCastBox, extra: T)->s32
{
    let value: s32 = box
    return value
}

func localClonePayloadOpSet(value: s32)->ClonePayloadSetTarget
{
    let target: ClonePayloadSetTarget = value
    return target
}

func(T) genericClonePayloadOpSetBody(value: s32, extra: T)->ClonePayloadSetTarget
{
    let target: ClonePayloadSetTarget = value
    return target
}

func(T) genericClonePayloadExplicitOpSetBody(value: s32, extra: T)->ClonePayloadSetTarget
{
    var target: ClonePayloadSetTarget
    target.opSet(value)
    return target
}

func(T) genericClonePayloadAssignBody(value: s32, extra: T)->ClonePayloadSetTarget
{
    var target: ClonePayloadSetTarget
    target = value
    return target
}

#test
{
    gClonePayloadOpCastCalls = 0

    let result = genericClonePayloadOpCastBody(ClonePayloadCastBox{value: 41}, true)

    @assert(gClonePayloadOpCastCalls == 1)
    @assert(result == 42)
}

#test
{
    gClonePayloadOpSetCalls = 0

    let result = localClonePayloadOpSet(40)

    @assert(result.value == 42)
    @assert(result.calls == 1)
    @assert(result.sentinel == 77)
    @assert(gClonePayloadOpSetCalls == 1)
}

#test
{
    gClonePayloadOpSetCalls = 0

    let result = genericClonePayloadExplicitOpSetBody(40, true)

    @assert(result.value == 42)
    @assert(result.calls == 1)
    @assert(result.sentinel == 77)
    @assert(gClonePayloadOpSetCalls == 1)
}

#test
{
    gClonePayloadOpSetCalls = 0

    let result = genericClonePayloadOpSetBody(40, true)

    @assert(result.value == 42)
    @assert(result.calls == 1)
    @assert(result.sentinel == 77)
    @assert(gClonePayloadOpSetCalls == 1)
}

#test
{
    gClonePayloadOpSetCalls = 0

    let result = genericClonePayloadAssignBody(40, true)

    @assert(result.value == 42)
    @assert(result.calls == 1)
    @assert(result.sentinel == 77)
    @assert(gClonePayloadOpSetCalls == 1)
}
