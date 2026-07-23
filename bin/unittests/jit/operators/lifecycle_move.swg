#global private
// This file asserts the RAW copy/move/drop mechanics, including reading storage
// abandoned by '#relocate': lifecycle safety (use-after-move check + poisoning) is
// disabled for the whole file. See bin/unittests/safety/use_after_move.swg for the
// lifecycle-safety behavior itself.
#global #[Swag.Safety(.Lifecycle, false), Swag.Sanity(.Lifecycle, false)]

var DropCount: u32 = 0
var DropTrace: s64 = 0
var PostCopyCount: u32 = 0
var PostMoveCount: u32 = 0

func resetLifecycleHooks()
{
    DropCount = 0
    DropTrace = 0
    PostCopyCount = 0
    PostMoveCount = 0
}

struct LifecycleInfo
{
    dst: s32
    src: s32
    drops: u32
    dropTrace: s64
    postCopy: u32
    postMove: u32
}

struct Tracked
{
    value: s32 = 5
}

impl Tracked
{
    mtd opDrop()
    {
        DropCount += 1
        DropTrace = DropTrace * 100 + cast(s64) .value
    }

    mtd opPostCopy()
    {
        PostCopyCount += 1
        .value += 10
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
        .value += 20
    }
}

struct ReturnedTracked
{
    value: s32 = 5
    a: s64
    b: s64
}

impl ReturnedTracked
{
    mtd opDrop()
    {
        DropCount += 1
        DropTrace = DropTrace * 100 + cast(s64) .value
    }

    mtd opPostCopy()
    {
        PostCopyCount += 1
        .value += 10
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
        .value += 20
    }
}

struct EmbeddedTracked
{
    inner: Tracked
}

struct LargeTracked
{
    a: u64
    b: u64
    c: u64
    d: u64
    item: Tracked
}

struct EmbeddedTrackedWithOps
{
    inner: Tracked
}

impl EmbeddedTrackedWithOps
{
    mtd opDrop()
    {
        DropCount += 1
        DropTrace = DropTrace * 100 + 90
    }

    mtd opPostCopy()
    {
        PostCopyCount += 1
        .inner.value += 100
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
        .inner.value += 200
    }
}

struct ForeachTrackedValues
{
    item: Tracked
}

impl ForeachTrackedValues
{
    #[Macro]
    func(ptr: bool, back: bool) opVisit(me, stmt: #code(item, index))
    {
        #if ptr do
            #inject(stmt, item = &me.item, index = 0)
            #else do
            #inject(stmt, item = cast(&Tracked) &me.item, index = 0)
    }
}

func assignTracked(dst: &Tracked, src: #move Tracked)
{
    dst = #move src
}

func assignTracked(dst: &Tracked, src: Tracked)
{
    dst = src
}

func takeTracked(src: Tracked)->s32
{
    return src.value
}

func takeLargeTrackedAddress(src: LargeTracked)->s32
{
    let ptr: const *LargeTracked = &src
    return ptr.item.value
}

func copyAssignInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var dst = Tracked{1}
    var src = Tracked{2}
    dst = src
    return {dst.value, src.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func moveAssignInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var dst = Tracked{7}
    var src = Tracked{3}
    dst = #move src
    return {dst.value, src.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func noDropCopyInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var dst = Tracked{9}
    var src = Tracked{4}
    dst = #nodrop src
    return {dst.value, src.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func noDropMoveInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var dst = Tracked{6}
    var src = Tracked{6}
    dst = #nodrop #move src
    return {dst.value, src.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func dropRelocateInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var dst = Tracked{8}
    var src = Tracked{3}
    @drop(&dst)
    dst = #relocate src
    return {dst.value, src.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func relocateInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var dst = Tracked{8}
    var src = Tracked{3}
    dst = #relocate src
    return {dst.value, src.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func selfCopyInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var value = Tracked{6}
    value = value
    return {value.value, value.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func selfMoveInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var value = Tracked{6}
    value = #move value
    return {value.value, value.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func moveRefAssignInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var dst = Tracked{6}
    var src = Tracked{4}
    assignTracked(&dst, #move src)
    return {dst.value, src.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func sliceMoveRefAssignInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var dst: Tracked
    var src: [2] Tracked = [Tracked{1}, Tracked{2}]
    let slice = @mkslice(&src[0], 2)
    assignTracked(&dst, #move slice[0])
    return {dst.value, src[0].value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func overloadCopyInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var dst: Tracked
    var src = Tracked{9}
    assignTracked(&dst, src)
    return {dst.value, src.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func overloadMoveInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var dst: Tracked
    var src = Tracked{9}
    assignTracked(&dst, #move src)
    return {dst.value, src.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func foreachOverloadCopyInfo()->LifecycleInfo
{
    var dst: Tracked
    var values = ForeachTrackedValues{Tracked{9}}
    resetLifecycleHooks()
    for value in values do
        assignTracked(&dst, value)
    return {dst.value, values.item.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func foreachOverloadMoveInfo()->LifecycleInfo
{
    var dst: Tracked
    var values = ForeachTrackedValues{Tracked{9}}
    resetLifecycleHooks()
    for value in values do
        assignTracked(&dst, #move value)
    return {dst.value, values.item.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func borrowedParamInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var src = Tracked{7}
    let value = takeTracked(src)
    return {value, src.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func borrowedAddressableParamInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var src = LargeTracked{1, 2, 3, 4, Tracked{7}}
    let value = takeLargeTrackedAddress(src)
    return {value, src.item.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func embeddedCopyAssignInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var dst = EmbeddedTracked{Tracked{1}}
    var src = EmbeddedTracked{Tracked{2}}
    dst = src
    return {dst.inner.value, src.inner.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func embeddedMoveAssignInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var dst = EmbeddedTracked{Tracked{7}}
    var src = EmbeddedTracked{Tracked{3}}
    dst = #move src
    return {dst.inner.value, src.inner.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func embeddedOuterCopyAssignInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var dst = EmbeddedTrackedWithOps{Tracked{4}}
    var src = EmbeddedTrackedWithOps{Tracked{5}}
    dst = src
    return {dst.inner.value, src.inner.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func embeddedOuterMoveAssignInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var dst = EmbeddedTrackedWithOps{Tracked{8}}
    var src = EmbeddedTrackedWithOps{Tracked{3}}
    dst = #move src
    return {dst.inner.value, src.inner.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func embeddedOuterNoDropCopyAssignInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var dst = EmbeddedTrackedWithOps{Tracked{6}}
    var src = EmbeddedTrackedWithOps{Tracked{2}}
    dst = #nodrop src
    return {dst.inner.value, src.inner.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

#[NoInline]
func makeTrackedReturn()->ReturnedTracked
{
    var value = ReturnedTracked{4, 0, 0}
    return value
}

func returnCopyInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    let value = makeTrackedReturn()
    return {value.value, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

#test
{
    let v = copyAssignInfo()
    @assert(v.dst == 12)
    @assert(v.src == 2)
    @assert(v.drops == 1)
    @assert(v.dropTrace == 1)
    @assert(v.postCopy == 1)
    @assert(v.postMove == 0)
}

#test
{
    let v = moveAssignInfo()
    @assert(v.dst == 23)
    @assert(v.src == 5)
    @assert(v.drops == 1)
    @assert(v.dropTrace == 7)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 1)
}

#test
{
    let v = noDropCopyInfo()
    @assert(v.dst == 14)
    @assert(v.src == 4)
    @assert(v.drops == 0)
    @assert(v.dropTrace == 0)
    @assert(v.postCopy == 1)
    @assert(v.postMove == 0)
}

#test
{
    let v = noDropMoveInfo()
    @assert(v.dst == 26)
    @assert(v.src == 5)
    @assert(v.drops == 0)
    @assert(v.dropTrace == 0)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 1)
}

#test
{
    let v = dropRelocateInfo()
    @assert(v.dst == 23)
    @assert(v.src == 3)
    @assert(v.drops == 1)
    @assert(v.dropTrace == 8)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 1)
}

#test
{
    let v = relocateInfo()
    @assert(v.dst == 23)
    @assert(v.src == 3)
    @assert(v.drops == 0)
    @assert(v.dropTrace == 0)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 1)
}

#test
{
    let v = selfCopyInfo()
    @assert(v.dst == 6)
    @assert(v.src == 6)
    @assert(v.drops == 0)
    @assert(v.dropTrace == 0)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 0)
}

#test
{
    let v = selfMoveInfo()
    @assert(v.dst == 6)
    @assert(v.src == 6)
    @assert(v.drops == 0)
    @assert(v.dropTrace == 0)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 0)
}

#test
{
    let v = moveRefAssignInfo()
    @assert(v.dst == 24)
    @assert(v.src == 5)
    @assert(v.drops == 1)
    @assert(v.dropTrace == 6)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 1)
}

#test
{
    let v = overloadCopyInfo()
    @assert(v.dst == 19)
    @assert(v.src == 9)
    @assert(v.drops == 1)
    @assert(v.dropTrace == 5)
    @assert(v.postCopy == 1)
    @assert(v.postMove == 0)
}

#test
{
    let v = overloadMoveInfo()
    @assert(v.dst == 29)
    @assert(v.src == 5)
    @assert(v.drops == 1)
    @assert(v.dropTrace == 5)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 1)
}

#test
{
    let v = borrowedParamInfo()
    @assert(v.dst == 7)
    @assert(v.src == 7)
    @assert(v.drops == 0)
    @assert(v.dropTrace == 0)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 0)
}

#test
{
    let v = borrowedAddressableParamInfo()
    @assert(v.dst == 7)
    @assert(v.src == 7)
    @assert(v.drops == 0)
    @assert(v.dropTrace == 0)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 0)
}

#test
{
    let v = embeddedCopyAssignInfo()
    @assert(v.dst == 12)
    @assert(v.src == 2)
    @assert(v.drops == 1)
    @assert(v.dropTrace == 1)
    @assert(v.postCopy == 1)
    @assert(v.postMove == 0)
}

#test
{
    let v = embeddedMoveAssignInfo()
    @assert(v.dst == 23)
    @assert(v.src == 5)
    @assert(v.drops == 1)
    @assert(v.dropTrace == 7)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 1)
}

#test
{
    let v = embeddedOuterCopyAssignInfo()
    @assert(v.dst == 115)
    @assert(v.src == 5)
    @assert(v.drops == 2)
    @assert(v.dropTrace == 9004)
    @assert(v.postCopy == 2)
    @assert(v.postMove == 0)
}

#test
{
    let v = embeddedOuterMoveAssignInfo()
    @assert(v.dst == 223)
    @assert(v.src == 5)
    @assert(v.drops == 2)
    @assert(v.dropTrace == 9008)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 2)
}

#test
{
    let v = embeddedOuterNoDropCopyAssignInfo()
    @assert(v.dst == 112)
    @assert(v.src == 2)
    @assert(v.drops == 0)
    @assert(v.dropTrace == 0)
    @assert(v.postCopy == 2)
    @assert(v.postMove == 0)
}

#test
{
    let v = returnCopyInfo()
    @assert(v.dst == 14)
    @assert(v.src == 0)
}

#test
{
    let v = sliceMoveRefAssignInfo()
    @assert(v.dst == 21)
    @assert(v.src == 5)
    @assert(v.drops == 1)
    @assert(v.dropTrace == 5)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 1)
}

#test
{
    let v = foreachOverloadCopyInfo()
    @assert(v.dst == 19)
    @assert(v.src == 9)
    @assert(v.drops == 1)
    @assert(v.dropTrace == 5)
    @assert(v.postCopy == 1)
    @assert(v.postMove == 0)
}

#test
{
    let v = foreachOverloadMoveInfo()
    @assert(v.dst == 29)
    @assert(v.src == 5)
    @assert(v.drops == 1)
    @assert(v.dropTrace == 5)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 1)
}

// A struct exposing a user `opSet` reachable from its own type through an implicit `opCast`, just like
// core.String (`opCast->string` + `opSet(string)`). The raw-storage modifiers `#relocate` and `#nodrop`
// (without `#move`) must bypass `opSet` and write the storage bitwise: routing them through `opSet`
// reads the uninitialized target (its buffer/allocator), which crashed Array.popBack of a heap string.
var SetCount: u32 = 0

struct Settable
{
    value: s32 = 0
}

impl Settable
{
    #[Implicit]
    mtd const opCast()->s32 => .value

    #[Implicit]
    mtd opSet(v: s32)
    {
        SetCount += 1
        .value = v
    }

    mtd opPostCopy()
    {
        PostCopyCount += 1
        .value += 10
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
        .value += 20
    }

    mtd opDrop()
    {
        DropCount += 1
    }
}

struct SettableInfo
{
    dst:      s32
    sets:     u32
    postCopy: u32
    postMove: u32
}

func settablePlainCopy()->SettableInfo
{
    resetLifecycleHooks()
    SetCount = 0
    var dst = Settable{1}
    var src = Settable{2}
    dst = src
    return {dst.value, SetCount, PostCopyCount, PostMoveCount}
}

func settableNoDropCopy()->SettableInfo
{
    resetLifecycleHooks()
    SetCount = 0
    var dst = Settable{9}
    var src = Settable{4}
    dst = #nodrop src
    return {dst.value, SetCount, PostCopyCount, PostMoveCount}
}

func settableRelocate()->SettableInfo
{
    resetLifecycleHooks()
    SetCount = 0
    var dst = Settable{8}
    var src = Settable{3}
    dst = #relocate src
    return {dst.value, SetCount, PostCopyCount, PostMoveCount}
}

#test
{
    // Plain assignment resolves the user `opSet`.
    let v = settablePlainCopy()
    @assert(v.sets == 1)
    @assert(v.dst == 2)
    @assert(v.postCopy == 0)
}

#test
{
    // `#nodrop` copy bypasses `opSet`: bitwise copy + opPostCopy into the uninitialized target.
    let v = settableNoDropCopy()
    @assert(v.sets == 0)
    @assert(v.dst == 14)
    @assert(v.postCopy == 1)
    @assert(v.postMove == 0)
}

#test
{
    // `#relocate` bypasses `opSet`: raw bitwise move + opPostMove, no read of the target.
    let v = settableRelocate()
    @assert(v.sets == 0)
    @assert(v.dst == 23)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 1)
}
