#global private
// This file asserts the RAW copy/move/drop mechanics, including reading storage
// abandoned by '#relocate': lifecycle safety (use-after-move check + poisoning) is
// disabled for the whole file. See bin/unittests/safety/use_after_move.swg for the
// lifecycle-safety behavior itself.
#global #[Swag.Safety(.Lifecycle, false), Swag.Sanity(.Lifecycle, false)]

var DropCount:     u32 = 0
var DropTrace:     s64 = 0
var PostCopyCount: u32 = 0
var PostMoveCount: u32 = 0

func resetLifecycleHooks()
{
    DropCount     = 0
    DropTrace     = 0
    PostCopyCount = 0
    PostMoveCount = 0
}

struct LifecycleInfo
{
    dst:       s32
    src:       s32
    drops:     u32
    dropTrace: s64
    postCopy:  u32
    postMove:  u32
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
        .value        += 10
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
        .value        += 20
    }
}

struct ReturnedTracked
{
    value: s32 = 5
    a:     s64
    b:     s64
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
        .value        += 10
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
        .value        += 20
    }
}

struct EmbeddedTracked
{
    inner: Tracked
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
        .inner.value  += 100
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
        .inner.value  += 200
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

func semaTest001()
{
    const V = #run copyAssignInfo()
    #assert(V.dst == 12)
    #assert(V.src == 2)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 1)
    #assert(V.postCopy == 1)
    #assert(V.postMove == 0)
}

func semaTest002()
{
    const V = #run moveAssignInfo()
    #assert(V.dst == 23)
    #assert(V.src == 5)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 7)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 1)
}

func semaTest003()
{
    const V = #run noDropCopyInfo()
    #assert(V.dst == 14)
    #assert(V.src == 4)
    #assert(V.drops == 0)
    #assert(V.dropTrace == 0)
    #assert(V.postCopy == 1)
    #assert(V.postMove == 0)
}

func semaTest004()
{
    const V = #run noDropMoveInfo()
    #assert(V.dst == 26)
    #assert(V.src == 5)
    #assert(V.drops == 0)
    #assert(V.dropTrace == 0)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 1)
}

func semaTest005()
{
    const V = #run dropRelocateInfo()
    #assert(V.dst == 23)
    #assert(V.src == 3)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 8)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 1)
}

func semaTest006()
{
    const V = #run relocateInfo()
    #assert(V.dst == 23)
    #assert(V.src == 3)
    #assert(V.drops == 0)
    #assert(V.dropTrace == 0)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 1)
}

func semaTest007()
{
    const V = #run selfCopyInfo()
    #assert(V.dst == 6)
    #assert(V.src == 6)
    #assert(V.drops == 0)
    #assert(V.dropTrace == 0)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 0)
}

func semaTest008()
{
    const V = #run selfMoveInfo()
    #assert(V.dst == 6)
    #assert(V.src == 6)
    #assert(V.drops == 0)
    #assert(V.dropTrace == 0)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 0)
}

func semaTest009()
{
    const V = #run moveRefAssignInfo()
    #assert(V.dst == 24)
    #assert(V.src == 5)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 6)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 1)
}

func semaTest010()
{
    const V = #run overloadCopyInfo()
    #assert(V.dst == 19)
    #assert(V.src == 9)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 5)
    #assert(V.postCopy == 1)
    #assert(V.postMove == 0)
}

func semaTest011()
{
    const V = #run overloadMoveInfo()
    #assert(V.dst == 29)
    #assert(V.src == 5)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 5)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 1)
}

func semaTest012()
{
    const V = #run borrowedParamInfo()
    #assert(V.dst == 7)
    #assert(V.src == 7)
    #assert(V.drops == 0)
    #assert(V.dropTrace == 0)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 0)
}

func semaTest013()
{
    const V = #run embeddedCopyAssignInfo()
    #assert(V.dst == 12)
    #assert(V.src == 2)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 1)
    #assert(V.postCopy == 1)
    #assert(V.postMove == 0)
}

func semaTest014()
{
    const V = #run embeddedMoveAssignInfo()
    #assert(V.dst == 23)
    #assert(V.src == 5)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 7)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 1)
}

func semaTest015()
{
    const V = #run embeddedOuterCopyAssignInfo()
    #assert(V.dst == 115)
    #assert(V.src == 5)
    #assert(V.drops == 2)
    #assert(V.dropTrace == 9004)
    #assert(V.postCopy == 2)
    #assert(V.postMove == 0)
}

func semaTest016()
{
    const V = #run embeddedOuterMoveAssignInfo()
    #assert(V.dst == 223)
    #assert(V.src == 5)
    #assert(V.drops == 2)
    #assert(V.dropTrace == 9008)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 2)
}

func semaTest017()
{
    const V = #run embeddedOuterNoDropCopyAssignInfo()
    #assert(V.dst == 112)
    #assert(V.src == 2)
    #assert(V.drops == 0)
    #assert(V.dropTrace == 0)
    #assert(V.postCopy == 2)
    #assert(V.postMove == 0)
}

func semaTest018()
{
    const V = #run returnCopyInfo()
    #assert(V.dst == 14)
    #assert(V.src == 0)
}

func semaTest019()
{
    const V = #run sliceMoveRefAssignInfo()
    #assert(V.dst == 21)
    #assert(V.src == 5)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 5)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 1)
}

func semaTest020()
{
    const V = #run foreachOverloadCopyInfo()
    #assert(V.dst == 19)
    #assert(V.src == 9)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 5)
    #assert(V.postCopy == 1)
    #assert(V.postMove == 0)
}

func semaTest021()
{
    const V = #run foreachOverloadMoveInfo()
    #assert(V.dst == 29)
    #assert(V.src == 5)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 5)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 1)
}
