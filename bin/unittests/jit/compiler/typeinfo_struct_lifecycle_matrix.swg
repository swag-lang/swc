#global private
using Swag

var DropHits: s32
var CopyHits: s32
var MoveHits: s32

struct Pod
{
    value: s32
}

struct Empty {}

struct(T) GenericPod
{
    value: T
}

struct DropOnly
{
    value: s32
}

impl DropOnly
{
    mtd opDrop()
    {
        DropHits += 1
    }
}

struct CopyOnly
{
    value: s32
}

impl CopyOnly
{
    mtd opPostCopy()
    {
        CopyHits += 1
        .value   += 10
    }
}

struct MoveOnly
{
    value: s32
}

impl MoveOnly
{
    mtd opPostMove()
    {
        MoveHits += 1
        .value   += 100
    }
}

struct WrappedDropOnly
{
    value: DropOnly
}

struct WrappedCopyOnly
{
    value: CopyOnly
}

struct WrappedMoveOnly
{
    value: MoveOnly
}

struct MixedLifecycle
{
    dropValue: DropOnly
    copyValue: CopyOnly
    moveValue: MoveOnly
    padding:   s32
}

struct(T) GenericBox
{
    value: T
}

struct InitOnly
{
    value: s32 = 17
    ready: bool = true
}

struct WrappedInitOnly
{
    value: InitOnly
}

func resetCounts()
{
    DropHits = 0
    CopyHits = 0
    MoveHits = 0
}

func typeStruct(type: typeinfo)->const *Swag.TypeInfoStruct
{
    return cast(const *Swag.TypeInfoStruct) type
}

func hasDropFlag(type: typeinfo)->bool => (type.flags & Swag.TypeInfoFlags.HasDrop) ? true : false
func hasCopyFlag(type: typeinfo)->bool => (type.flags & Swag.TypeInfoFlags.HasPostCopy) ? true : false
func hasMoveFlag(type: typeinfo)->bool => (type.flags & Swag.TypeInfoFlags.HasPostMove) ? true : false
func hasInitPointer(type: typeinfo)->bool => typeStruct(type).opInit != null
func hasDropPointer(type: typeinfo)->bool => typeStruct(type).opDrop != null
func hasCopyPointer(type: typeinfo)->bool => typeStruct(type).opPostCopy != null
func hasMovePointer(type: typeinfo)->bool => typeStruct(type).opPostMove != null

func hasLifecycleShape(type: typeinfo, wantDrop: bool, wantCopy: bool, wantMove: bool)->bool
{
    return hasDropFlag(type) == wantDrop and
           hasDropPointer(type) == wantDrop and
           hasCopyFlag(type) == wantCopy and
           hasCopyPointer(type) == wantCopy and
           hasMoveFlag(type) == wantMove and
           hasMovePointer(type) == wantMove
}

func runDrop(type: typeinfo, value: *void)
{
    let info = typeStruct(type)
    info.opDrop(value)
}

func runInit(type: typeinfo, value: *void)
{
    let info = typeStruct(type)
    info.opInit(value)
}

func runCopy(type: typeinfo, value: *void)
{
    let info = typeStruct(type)
    info.opPostCopy(value)
}

func runMove(type: typeinfo, value: *void)
{
    let info = typeStruct(type)
    info.opPostMove(value)
}

func podShapesStayEmpty()->bool
{
    return hasLifecycleShape(#typeof(Pod), false, false, false) and
           hasInitPointer(#typeof(Pod)) and
           hasLifecycleShape(#typeof(Empty), false, false, false) and
           hasInitPointer(#typeof(Empty)) and
           hasLifecycleShape(#typeof(GenericPod's32), false, false, false) and
           hasInitPointer(#typeof(GenericPod's32)) and
           hasLifecycleShape(#typeof(GenericBox'Pod), false, false, false) and
           hasInitPointer(#typeof(GenericBox'Pod))
}

func initPointersRestoreDefaults()->bool
{
    if !hasInitPointer(#typeof(InitOnly)) do
        return false
    if !hasInitPointer(#typeof(WrappedInitOnly)) do
        return false
    if !hasInitPointer(#typeof(GenericBox'InitOnly)) do
        return false

    var direct = InitOnly{value: 0, ready: false}
    runInit(#typeof(InitOnly), &direct)
    if direct.value != 17 or !direct.ready do
        return false

    var wrapped = WrappedInitOnly{value: InitOnly{value: 0, ready: false}}
    runInit(#typeof(WrappedInitOnly), &wrapped)
    if wrapped.value.value != 17 or !wrapped.value.ready do
        return false

    var genericValue = GenericBox'InitOnly{value: InitOnly{value: 0, ready: false}}
    runInit(#typeof(GenericBox'InitOnly), &genericValue)
    return genericValue.value.value == 17 and genericValue.value.ready
}

func directPartialLifecyclePointersWork()->bool
{
    if !hasLifecycleShape(#typeof(DropOnly), true, false, false) do
        return false
    if !hasLifecycleShape(#typeof(CopyOnly), false, true, false) do
        return false
    if !hasLifecycleShape(#typeof(MoveOnly), false, false, true) do
        return false

    resetCounts()
    var dropValue = DropOnly{}
    runDrop(#typeof(DropOnly), &dropValue)
    if DropHits != 1 or CopyHits != 0 or MoveHits != 0 do
        return false

    resetCounts()
    var copyValue = CopyOnly{value: 5}
    runCopy(#typeof(CopyOnly), &copyValue)
    if DropHits != 0 or CopyHits != 1 or MoveHits != 0 or copyValue.value != 15 do
        return false

    resetCounts()
    var moveValue = MoveOnly{value: 7}
    runMove(#typeof(MoveOnly), &moveValue)
    return DropHits == 0 and CopyHits == 0 and MoveHits == 1 and moveValue.value == 107
}

func synthesizedPartialLifecyclePointersWork()->bool
{
    if !hasLifecycleShape(#typeof(WrappedDropOnly), true, false, false) do
        return false
    if !hasLifecycleShape(#typeof(WrappedCopyOnly), false, true, false) do
        return false
    if !hasLifecycleShape(#typeof(WrappedMoveOnly), false, false, true) do
        return false

    resetCounts()
    var dropValue = WrappedDropOnly{}
    runDrop(#typeof(WrappedDropOnly), &dropValue)
    if DropHits != 1 or CopyHits != 0 or MoveHits != 0 do
        return false

    resetCounts()
    var copyValue = WrappedCopyOnly{value: CopyOnly{value: 8}}
    runCopy(#typeof(WrappedCopyOnly), &copyValue)
    if DropHits != 0 or CopyHits != 1 or MoveHits != 0 or copyValue.value.value != 18 do
        return false

    resetCounts()
    var moveValue = WrappedMoveOnly{value: MoveOnly{value: 4}}
    runMove(#typeof(WrappedMoveOnly), &moveValue)
    return DropHits == 0 and CopyHits == 0 and MoveHits == 1 and moveValue.value.value == 104
}

func mixedLifecycleFlagsMatchPointers()->bool
{
    let type = #typeof(MixedLifecycle)
    if !hasLifecycleShape(type, true, true, true) do
        return false

    resetCounts()
    var value = MixedLifecycle{dropValue: DropOnly{}, copyValue: CopyOnly{value: 2}, moveValue: MoveOnly{value: 3}}
    runCopy(type, &value)
    if DropHits != 0 or CopyHits != 1 or MoveHits != 0 or value.copyValue.value != 12 or value.moveValue.value != 3 do
        return false

    resetCounts()
    runMove(type, &value)
    if DropHits != 0 or CopyHits != 0 or MoveHits != 1 or value.moveValue.value != 103 or value.copyValue.value != 12 do
        return false

    resetCounts()
    runDrop(type, &value)
    return DropHits == 1 and CopyHits == 0 and MoveHits == 0
}

func genericMatrixStaysAligned()->bool
{
    if !hasLifecycleShape(#typeof(GenericBox'DropOnly), true, false, false) do
        return false
    if !hasLifecycleShape(#typeof(GenericBox'CopyOnly), false, true, false) do
        return false
    if !hasLifecycleShape(#typeof(GenericBox'MoveOnly), false, false, true) do
        return false
    if !hasLifecycleShape(#typeof(GenericBox'MixedLifecycle), true, true, true) do
        return false

    resetCounts()
    var copyValue = GenericBox'CopyOnly{value: CopyOnly{value: 9}}
    runCopy(#typeof(GenericBox'CopyOnly), &copyValue)
    if DropHits != 0 or CopyHits != 1 or MoveHits != 0 or copyValue.value.value != 19 do
        return false

    resetCounts()
    var moveValue = GenericBox'MoveOnly{value: MoveOnly{value: 11}}
    runMove(#typeof(GenericBox'MoveOnly), &moveValue)
    if DropHits != 0 or CopyHits != 0 or MoveHits != 1 or moveValue.value.value != 111 do
        return false

    resetCounts()
    var mixedValue = GenericBox'MixedLifecycle{value: MixedLifecycle{dropValue: DropOnly{}, copyValue: CopyOnly{value: 1}, moveValue: MoveOnly{value: 6}}}
    runCopy(#typeof(GenericBox'MixedLifecycle), &mixedValue)
    if CopyHits != 1 or mixedValue.value.copyValue.value != 11 do
        return false

    resetCounts()
    runMove(#typeof(GenericBox'MixedLifecycle), &mixedValue)
    if MoveHits != 1 or mixedValue.value.moveValue.value != 106 do
        return false

    resetCounts()
    var dropValue = GenericBox'DropOnly{}
    runDrop(#typeof(GenericBox'DropOnly), &dropValue)
    return DropHits == 1
}

#test
{
    @assert(podShapesStayEmpty())
    @assert(initPointersRestoreDefaults())
    @assert(directPartialLifecyclePointersWork())
    @assert(synthesizedPartialLifecyclePointersWork())
    @assert(mixedLifecycleFlagsMatchPointers())
    @assert(genericMatrixStaysAligned())
}
