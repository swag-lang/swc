#global fileprivate
using Swag

var EventCount: s32
var Events: [32] s32

struct GenericProbe
{
    value: s32
}

impl GenericProbe
{
    mtd opDrop()
    {
        pushEvent(100 + .value)
    }

    mtd opPostCopy()
    {
        pushEvent(200 + .value)
        .value += 1
    }

    mtd opPostMove()
    {
        pushEvent(300 + .value)
        .value += 10
    }
}

struct(T) PairBox
{
    left:  T
    right: T
}

struct(T) GenericDirectAndField
{
    child: T
    stamp: s32
}

impl GenericDirectAndField
{
    mtd opDrop()
    {
        pushEvent(1)
    }

    mtd opPostCopy()
    {
        pushEvent(2)
        .stamp += 100
    }

    mtd opPostMove()
    {
        pushEvent(3)
        .stamp += 1000
    }
}

struct(T) NestedGenericLifecycle
{
    pair: PairBox'T
    tail: T
}

struct(T, N: s32) GenericArrayLifecycle
{
    values: [N] T
}

func pushEvent(value: s32)
{
    Events[EventCount] = value
    EventCount += 1
}

func resetEvents()
{
    EventCount = 0
}

func eventSum()->s32
{
    var result: s32
    for i in EventCount do
        result += Events[i]
    return result
}

func typeStruct(type: typeinfo)->const *Swag.TypeInfoStruct
{
    return cast(const *Swag.TypeInfoStruct) type
}

func hasDropFlag(type: typeinfo)->bool => (type.flags & Swag.TypeInfoFlags.HasDrop) ? true : false
func hasCopyFlag(type: typeinfo)->bool => (type.flags & Swag.TypeInfoFlags.HasPostCopy) ? true : false
func hasMoveFlag(type: typeinfo)->bool => (type.flags & Swag.TypeInfoFlags.HasPostMove) ? true : false

func hasLifecycleShape(type: typeinfo, wantDrop: bool, wantCopy: bool, wantMove: bool)->bool
{
    let info = typeStruct(type)
    return hasDropFlag(type) == wantDrop and
           (info.opDrop != null) == wantDrop and
           hasCopyFlag(type) == wantCopy and
           (info.opPostCopy != null) == wantCopy and
           hasMoveFlag(type) == wantMove and
           (info.opPostMove != null) == wantMove
}

func runDrop(type: typeinfo, value: *void)
{
    typeStruct(type).opDrop(value)
}

func runCopy(type: typeinfo, value: *void)
{
    typeStruct(type).opPostCopy(value)
}

func runMove(type: typeinfo, value: *void)
{
    typeStruct(type).opPostMove(value)
}

func genericPodInstancesStayPod()->bool
{
    return hasLifecycleShape(#typeof(PairBox's32), false, false, false) and
           hasLifecycleShape(#typeof(GenericArrayLifecycle'(u8, 4)), false, false, false) and
           hasLifecycleShape(#typeof(NestedGenericLifecycle's32), false, false, false)
}

func genericDirectAndFieldShapeWorks()->bool
{
    let type = #typeof(GenericDirectAndField'GenericProbe)
    return hasLifecycleShape(type, true, true, true)
}

func genericDirectAndFieldDropWorks()->bool
{
    let type = #typeof(GenericDirectAndField'GenericProbe)
    resetEvents()
    var value = GenericDirectAndField'GenericProbe{child: GenericProbe{value: 5}, stamp: 7}
    runDrop(type, &value)
    return EventCount == 2 and Events[0] == 1 and Events[1] == 105
}

func genericDirectAndFieldCopyWorks()->bool
{
    let type = #typeof(GenericDirectAndField'GenericProbe)
    resetEvents()
    var value = GenericDirectAndField'GenericProbe{child: GenericProbe{value: 5}, stamp: 7}
    runCopy(type, &value)
    @assert(EventCount == 2)
    @assert(Events[0] == 205)
    @assert(Events[1] == 2)
    @assert(value.child.value == 6)
    @assert(value.stamp == 107)
    return true
}

func genericDirectAndFieldMoveWorks()->bool
{
    let type = #typeof(GenericDirectAndField'GenericProbe)
    resetEvents()
    var value = GenericDirectAndField'GenericProbe{child: GenericProbe{value: 6}, stamp: 107}
    runMove(type, &value)
    @assert(EventCount == 2)
    @assert(Events[0] == 306)
    @assert(Events[1] == 3)
    @assert(value.child.value == 16)
    @assert(value.stamp == 1107)
    return true
}

func nestedGenericCompositionWorks()->bool
{
    let type = #typeof(NestedGenericLifecycle'GenericProbe)
    if !hasLifecycleShape(type, true, true, true) do
        return false

    var value = NestedGenericLifecycle'GenericProbe{pair: PairBox'GenericProbe{left: GenericProbe{value: 1}, right: GenericProbe{value: 2}}, tail: GenericProbe{value: 3}}

    resetEvents()
    runCopy(type, &value)
    if EventCount != 3 or eventSum() != 606 or value.pair.left.value != 2 or value.pair.right.value != 3 or value.tail.value != 4 do
        return false

    resetEvents()
    runMove(type, &value)
    if EventCount != 3 or eventSum() != 909 or value.pair.left.value != 12 or value.pair.right.value != 13 or value.tail.value != 14 do
        return false

    resetEvents()
    runDrop(type, &value)
    return EventCount == 3 and eventSum() == 339
}

func genericConstArrayLifecycleWorks()->bool
{
    let type = #typeof(GenericArrayLifecycle'(GenericProbe, 3))
    if !hasLifecycleShape(type, true, true, true) do
        return false

    var value: GenericArrayLifecycle'(GenericProbe, 3)
    value.values[0].value = 4
    value.values[1].value = 5
    value.values[2].value = 6

    resetEvents()
    runCopy(type, &value)
    if EventCount != 3 or eventSum() != 615 or value.values[0].value != 5 or value.values[1].value != 6 or value.values[2].value != 7 do
        return false

    resetEvents()
    runMove(type, &value)
    if EventCount != 3 or eventSum() != 918 or value.values[0].value != 15 or value.values[1].value != 16 or value.values[2].value != 17 do
        return false

    resetEvents()
    runDrop(type, &value)
    return EventCount == 3 and eventSum() == 348
}

#test
{
    @assert(genericPodInstancesStayPod())
    @assert(genericDirectAndFieldShapeWorks())
    @assert(genericDirectAndFieldDropWorks())
    @assert(genericDirectAndFieldCopyWorks())
    @assert(genericDirectAndFieldMoveWorks())
    @assert(nestedGenericCompositionWorks())
    @assert(genericConstArrayLifecycleWorks())
}
