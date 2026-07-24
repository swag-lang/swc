#global private
using Swag

var EventCount: s32
var Events:     [32] s32

struct EventProbe
{
    value: s32 = 11
}

impl EventProbe
{
    mtd opDrop()
    {
        pushEvent(100 + .value)
    }

    mtd opPostCopy()
    {
        pushEvent(200 + .value)
        .value += 10
    }

    mtd opPostMove()
    {
        pushEvent(300 + .value)
        .value += 100
    }
}

struct MiddleLifecycle
{
    left:   EventProbe
    right:  EventProbe
    marker: s32 = 22
}

impl MiddleLifecycle
{
    mtd opDrop()
    {
        pushEvent(10)
    }

    mtd opPostCopy()
    {
        pushEvent(20)
        .marker += 1000
    }

    mtd opPostMove()
    {
        pushEvent(30)
        .marker += 10000
    }
}

struct OuterLifecycle
{
    head:   EventProbe
    middle: MiddleLifecycle
    stamp:  s32 = 33
}

impl OuterLifecycle
{
    mtd opDrop()
    {
        pushEvent(1)
    }

    mtd opPostCopy()
    {
        pushEvent(2)
        .stamp += 100000
    }

    mtd opPostMove()
    {
        pushEvent(3)
        .stamp += 1000000
    }
}

struct ArrayLifecycle
{
    values: [3] EventProbe
}

struct DeepInitLifecycle
{
    outer: OuterLifecycle
    mids:  [2] MiddleLifecycle
    stamp: s32 = 77
}

func pushEvent(value: s32)
{
    Events[EventCount] = value
    EventCount         += 1
}

func resetEvents()
{
    EventCount = 0
}

func eventSum()->s32
{
    var result: s32
    for [i] in EventCount do
        result += Events[i]
    return result
}

func typeStruct(type: typeinfo)->const *Swag.TypeInfoStruct
{
    return cast(const *Swag.TypeInfoStruct) type
}

func hasDropFlag(type: typeinfo)->bool    => (type.flags & Swag.TypeInfoFlags.HasDrop) ? true : false
func hasCopyFlag(type: typeinfo)->bool    => (type.flags & Swag.TypeInfoFlags.HasPostCopy) ? true : false
func hasMoveFlag(type: typeinfo)->bool    => (type.flags & Swag.TypeInfoFlags.HasPostMove) ? true : false
func hasInitPointer(type: typeinfo)->bool => typeStruct(type).opInit != null

func hasAllLifecyclePointers(type: typeinfo)->bool
{
    let info = typeStruct(type)
    return hasInitPointer(type) and
           hasDropFlag(type) and
           hasCopyFlag(type) and
           hasMoveFlag(type) and
           info.opDrop != null and
           info.opPostCopy != null and
           info.opPostMove != null
}

func runInit(type: typeinfo, value: *void)
{
    let op = notnull typeStruct(type).opInit
    op(value)
}

func runDrop(type: typeinfo, value: *void)
{
    let op = notnull typeStruct(type).opDrop
    op(value)
}

func runCopy(type: typeinfo, value: *void)
{
    let op = notnull typeStruct(type).opPostCopy
    op(value)
}

func runMove(type: typeinfo, value: *void)
{
    let op = notnull typeStruct(type).opPostMove
    op(value)
}

func nestedDropOrderWorks()->bool
{
    let type = #typeof(OuterLifecycle)
    if !hasAllLifecyclePointers(type) do
        return false

    resetEvents()
    var value = OuterLifecycle{head: EventProbe{value: 1}, middle: MiddleLifecycle{left: EventProbe{value: 2}, right: EventProbe{value: 3}}, stamp: 9}
    runDrop(type, &value)
    return EventCount == 5 and Events[0] == 1 and Events[1] == 10 and Events[2] == 103 and Events[3] == 102 and Events[4] == 101
}

func nestedInitRestoresDefaults()->bool
{
    let type = #typeof(OuterLifecycle)
    if !hasAllLifecyclePointers(type) do
        return false

    var value = OuterLifecycle{head: EventProbe{value: 91}, middle: MiddleLifecycle{left: EventProbe{value: 92}, right: EventProbe{value: 93}, marker: -7}, stamp: -9}
    resetEvents()
    runInit(type, &value)
    return EventCount == 0 and
           value.head.value == 11 and
           value.middle.left.value == 11 and
           value.middle.right.value == 11 and
           value.middle.marker == 22 and
           value.stamp == 33
}

func nestedCopyOrderWorks()->bool
{
    let type = #typeof(OuterLifecycle)
    if !hasAllLifecyclePointers(type) do
        return false

    resetEvents()
    var value = OuterLifecycle{head: EventProbe{value: 1}, middle: MiddleLifecycle{left: EventProbe{value: 2}, right: EventProbe{value: 3}, marker: 7}, stamp: 9}
    runCopy(type, &value)
    return EventCount == 5 and
           Events[0] == 201 and
           Events[1] == 202 and
           Events[2] == 203 and
           Events[3] == 20 and
           Events[4] == 2 and
           value.head.value == 11 and
           value.middle.left.value == 12 and
           value.middle.right.value == 13 and
           value.middle.marker == 1007 and
           value.stamp == 100009
}

func nestedMoveOrderWorks()->bool
{
    let type = #typeof(OuterLifecycle)
    if !hasAllLifecyclePointers(type) do
        return false

    resetEvents()
    var value = OuterLifecycle{head: EventProbe{value: 1}, middle: MiddleLifecycle{left: EventProbe{value: 2}, right: EventProbe{value: 3}, marker: 7}, stamp: 9}
    runMove(type, &value)
    return EventCount == 5 and
           Events[0] == 301 and
           Events[1] == 302 and
           Events[2] == 303 and
           Events[3] == 30 and
           Events[4] == 3 and
           value.head.value == 101 and
           value.middle.left.value == 102 and
           value.middle.right.value == 103 and
           value.middle.marker == 10007 and
           value.stamp == 1000009
}

func arrayInitTouchesEveryElement()->bool
{
    let type = #typeof(ArrayLifecycle)
    if !hasAllLifecyclePointers(type) do
        return false

    var value: ArrayLifecycle
    value.values[0].value = 1
    value.values[1].value = 2
    value.values[2].value = 3

    resetEvents()
    runInit(type, &value)
    return EventCount == 0 and
           value.values[0].value == 11 and
           value.values[1].value == 11 and
           value.values[2].value == 11
}

func arrayLifecycleTouchesEveryElement()->bool
{
    let type = #typeof(ArrayLifecycle)
    if !hasAllLifecyclePointers(type) do
        return false

    var value: ArrayLifecycle
    value.values[0].value = 1
    value.values[1].value = 2
    value.values[2].value = 3

    resetEvents()
    runCopy(type, &value)
    if EventCount != 3 or eventSum() != 606 or value.values[0].value != 11 or value.values[1].value != 12 or value.values[2].value != 13 do
        return false

    resetEvents()
    runMove(type, &value)
    if EventCount != 3 or eventSum() != 936 or value.values[0].value != 111 or value.values[1].value != 112 or value.values[2].value != 113 do
        return false

    resetEvents()
    runDrop(type, &value)
    return EventCount == 3 and eventSum() == 636
}

func deepInitRestoresNestedArrays()->bool
{
    let type = #typeof(DeepInitLifecycle)
    if !hasAllLifecyclePointers(type) do
        return false

    var value: DeepInitLifecycle
    value.outer.head.value         = 41
    value.outer.middle.left.value  = 42
    value.outer.middle.right.value = 43
    value.outer.middle.marker      = 44
    value.outer.stamp              = 45
    value.mids[0].left.value       = 51
    value.mids[0].right.value      = 52
    value.mids[0].marker           = 53
    value.mids[1].left.value       = 61
    value.mids[1].right.value      = 62
    value.mids[1].marker           = 63
    value.stamp                    = 64

    resetEvents()
    runInit(type, &value)
    return EventCount == 0 and
           value.outer.head.value == 11 and
           value.outer.middle.left.value == 11 and
           value.outer.middle.right.value == 11 and
           value.outer.middle.marker == 22 and
           value.outer.stamp == 33 and
           value.mids[0].left.value == 11 and
           value.mids[0].right.value == 11 and
           value.mids[0].marker == 22 and
           value.mids[1].left.value == 11 and
           value.mids[1].right.value == 11 and
           value.mids[1].marker == 22 and
           value.stamp == 77
}

#test
{
    @assert(nestedDropOrderWorks())
    @assert(nestedInitRestoresDefaults())
    @assert(nestedCopyOrderWorks())
    @assert(nestedMoveOrderWorks())
    @assert(arrayInitTouchesEveryElement())
    @assert(arrayLifecycleTouchesEveryElement())
    @assert(deepInitRestoresNestedArrays())
}
