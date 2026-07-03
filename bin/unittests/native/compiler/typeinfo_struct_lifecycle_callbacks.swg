#global private
using Swag

var DropCount: s32
var PostCopyCount: s32
var PostMoveCount: s32

var EventCount: s32
var Events: [8] s32

struct LifecycleProbe
{
    value: s32
}

impl LifecycleProbe
{
    mtd opDrop()
    {
        DropCount += 1
    }

    mtd opPostCopy()
    {
        PostCopyCount += 1
        .value += 10
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
        .value += 100
    }
}

struct LifecycleContainer
{
    value: LifecycleProbe
}

struct(T) GenericLifecycleContainer
{
    value: T
}

struct(T) GenericDirectLifecycleProbe
{
    value: T
}

impl GenericDirectLifecycleProbe
{
    mtd opDrop()
    {
        DropCount += 10
    }

    mtd opPostCopy()
    {
        PostCopyCount += 10
    }

    mtd opPostMove()
    {
        PostMoveCount += 10
    }
}

func pushEvent(value: s32)
{
    Events[EventCount] = value
    EventCount += 1
}

struct OrderedLifecycleProbe
{
    value: s32
}

impl OrderedLifecycleProbe
{
    mtd opDrop()
    {
        pushEvent(2)
    }

    mtd opPostCopy()
    {
        pushEvent(3)
        .value += 1
    }

    mtd opPostMove()
    {
        pushEvent(4)
        .value += 10
    }
}

struct OrderedLifecycleContainer
{
    child: OrderedLifecycleProbe
    value: s32
}

impl OrderedLifecycleContainer
{
    mtd opDrop()
    {
        pushEvent(1)
    }

    mtd opPostCopy()
    {
        pushEvent(5)
        .value += 100
    }

    mtd opPostMove()
    {
        pushEvent(6)
        .value += 1000
    }
}

func resetCounts()
{
    DropCount = 0
    PostCopyCount = 0
    PostMoveCount = 0
}

func resetEvents()
{
    EventCount = 0
}

func typeStruct(type: typeinfo)->const *Swag.TypeInfoStruct
{
    return cast(const *Swag.TypeInfoStruct) type
}

func hasDropFlag(type: typeinfo)->bool => (type.flags & Swag.TypeInfoFlags.HasDrop) ? true : false
func hasPostCopyFlag(type: typeinfo)->bool => (type.flags & Swag.TypeInfoFlags.HasPostCopy) ? true : false
func hasPostMoveFlag(type: typeinfo)->bool => (type.flags & Swag.TypeInfoFlags.HasPostMove) ? true : false
func hasDropPointer(type: typeinfo)->bool => typeStruct(type).opDrop != null
func hasPostCopyPointer(type: typeinfo)->bool => typeStruct(type).opPostCopy != null
func hasPostMovePointer(type: typeinfo)->bool => typeStruct(type).opPostMove != null

func runDrop(type: typeinfo, value: *void)
{
    let info = typeStruct(type)
    info.opDrop(value)
}

func runPostCopy(type: typeinfo, value: *void)
{
    let info = typeStruct(type)
    info.opPostCopy(value)
}

func runPostMove(type: typeinfo, value: *void)
{
    let info = typeStruct(type)
    info.opPostMove(value)
}

func typeinfoDirectDropWorks()->bool
{
    resetCounts()

    if !hasDropFlag(#typeof(LifecycleProbe)) or !hasDropPointer(#typeof(LifecycleProbe)) do
        return false

    var value = LifecycleProbe{}
    runDrop(#typeof(LifecycleProbe), &value)
    return DropCount == 1
}

func typeinfoDirectCopyWorks()->bool
{
    resetCounts()

    if !hasPostCopyFlag(#typeof(LifecycleProbe)) or !hasPostCopyPointer(#typeof(LifecycleProbe)) do
        return false

    var value = LifecycleProbe{value: 5}
    runPostCopy(#typeof(LifecycleProbe), &value)
    return PostCopyCount == 1 and value.value == 15
}

func typeinfoDirectMoveWorks()->bool
{
    resetCounts()

    if !hasPostMoveFlag(#typeof(LifecycleProbe)) or !hasPostMovePointer(#typeof(LifecycleProbe)) do
        return false

    var value = LifecycleProbe{value: 7}
    runPostMove(#typeof(LifecycleProbe), &value)
    return PostMoveCount == 1 and value.value == 107
}

func typeinfoComposedLifecycleWorks()->bool
{
    resetCounts()

    let type = #typeof(LifecycleContainer)
    if !hasDropFlag(type) or !hasPostCopyFlag(type) or !hasPostMoveFlag(type) do
        return false
    if !hasDropPointer(type) or !hasPostCopyPointer(type) or !hasPostMovePointer(type) do
        return false

    var value = LifecycleContainer{value: LifecycleProbe{value: 4}}
    runPostCopy(type, &value)
    if PostCopyCount != 1 or value.value.value != 14 do
        return false

    runPostMove(type, &value)
    if PostMoveCount != 1 or value.value.value != 114 do
        return false

    runDrop(type, &value)
    return DropCount == 1
}

func typeinfoGenericComposedLifecycleWorks()->bool
{
    resetCounts()

    let type = #typeof(GenericLifecycleContainer'LifecycleProbe)
    @assert(hasDropFlag(type))
    @assert(hasPostCopyFlag(type))
    @assert(hasPostMoveFlag(type))
    @assert(hasDropPointer(type))
    @assert(hasPostCopyPointer(type))
    @assert(hasPostMovePointer(type))

    var value = GenericLifecycleContainer'LifecycleProbe{value: LifecycleProbe{value: 3}}
    runPostCopy(type, &value)
    @assert(PostCopyCount == 1)
    @assert(value.value.value == 13)

    runPostMove(type, &value)
    @assert(PostMoveCount == 1)
    @assert(value.value.value == 113)

    runDrop(type, &value)
    @assert(DropCount == 1)
    return true
}

func typeinfoGenericDirectLifecycleWorks()->bool
{
    resetCounts()

    let type = #typeof(GenericDirectLifecycleProbe's32)
    @assert(hasDropFlag(type))
    @assert(hasPostCopyFlag(type))
    @assert(hasPostMoveFlag(type))
    @assert(hasDropPointer(type))
    @assert(hasPostCopyPointer(type))
    @assert(hasPostMovePointer(type))

    var value = GenericDirectLifecycleProbe's32{value: 3}
    runPostCopy(type, &value)
    @assert(PostCopyCount == 10)

    runPostMove(type, &value)
    @assert(PostMoveCount == 10)

    runDrop(type, &value)
    @assert(DropCount == 10)
    return true
}

func typeinfoOrderedDropWorks()->bool
{
    resetEvents()

    let type = #typeof(OrderedLifecycleContainer)
    if !hasDropFlag(type) or !hasDropPointer(type) do
        return false

    var value = OrderedLifecycleContainer{}
    runDrop(type, &value)
    return EventCount == 2 and Events[0] == 1 and Events[1] == 2
}

func typeinfoOrderedCopyWorks()->bool
{
    resetEvents()

    let type = #typeof(OrderedLifecycleContainer)
    if !hasPostCopyFlag(type) or !hasPostCopyPointer(type) do
        return false

    var value = OrderedLifecycleContainer{child: OrderedLifecycleProbe{value: 8}, value: 11}
    runPostCopy(type, &value)
    return EventCount == 2 and
        Events[0] == 3 and
        Events[1] == 5 and
        value.child.value == 9 and
        value.value == 111
}

func typeinfoOrderedMoveWorks()->bool
{
    resetEvents()

    let type = #typeof(OrderedLifecycleContainer)
    if !hasPostMoveFlag(type) or !hasPostMovePointer(type) do
        return false

    var value = OrderedLifecycleContainer{child: OrderedLifecycleProbe{value: 8}, value: 11}
    runPostMove(type, &value)
    return EventCount == 2 and
        Events[0] == 4 and
        Events[1] == 6 and
        value.child.value == 18 and
        value.value == 1011
}

#test
{
    @assert(typeinfoDirectDropWorks())
    @assert(typeinfoDirectCopyWorks())
    @assert(typeinfoDirectMoveWorks())
    @assert(typeinfoComposedLifecycleWorks())
    @assert(typeinfoGenericComposedLifecycleWorks())
    @assert(typeinfoGenericDirectLifecycleWorks())
    @assert(typeinfoOrderedDropWorks())
    @assert(typeinfoOrderedCopyWorks())
    @assert(typeinfoOrderedMoveWorks())
}
