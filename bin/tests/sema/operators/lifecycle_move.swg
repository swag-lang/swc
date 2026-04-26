#global fileprivate

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
        .inner.value += 100
    }

    mtd opPostMove()
    {
        PostMoveCount += 1
        .inner.value += 200
    }
}

func assignTracked(dst: &Tracked, src: &&Tracked)
{
    dst = #move src
}

func assignTracked(dst: &Tracked, src: Tracked)
{
    dst = src
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

func moveRawInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var dst = Tracked{8}
    var src = Tracked{3}
    dst = #moveraw src
    return {dst.value, src.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func noDropMoveRawInfo()->LifecycleInfo
{
    resetLifecycleHooks()
    var dst = Tracked{8}
    var src = Tracked{3}
    dst = #nodrop #moveraw src
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
    var rr: &&Tracked = moveref &src
    dst = #move rr
    return {dst.value, src.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
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
    assignTracked(&dst, moveref &src)
    return {dst.value, src.value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
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

#test
{
    const V = #run copyAssignInfo()
    #assert(V.dst == 12)
    #assert(V.src == 2)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 1)
    #assert(V.postCopy == 1)
    #assert(V.postMove == 0)
}

#test
{
    const V = #run moveAssignInfo()
    #assert(V.dst == 23)
    #assert(V.src == 5)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 7)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 1)
}

#test
{
    const V = #run noDropCopyInfo()
    #assert(V.dst == 14)
    #assert(V.src == 4)
    #assert(V.drops == 0)
    #assert(V.dropTrace == 0)
    #assert(V.postCopy == 1)
    #assert(V.postMove == 0)
}

#test
{
    const V = #run noDropMoveInfo()
    #assert(V.dst == 26)
    #assert(V.src == 5)
    #assert(V.drops == 0)
    #assert(V.dropTrace == 0)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 1)
}

#test
{
    const V = #run moveRawInfo()
    #assert(V.dst == 23)
    #assert(V.src == 3)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 8)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 1)
}

#test
{
    const V = #run noDropMoveRawInfo()
    #assert(V.dst == 23)
    #assert(V.src == 3)
    #assert(V.drops == 0)
    #assert(V.dropTrace == 0)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 1)
}

#test
{
    const V = #run selfCopyInfo()
    #assert(V.dst == 6)
    #assert(V.src == 6)
    #assert(V.drops == 0)
    #assert(V.dropTrace == 0)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 0)
}

#test
{
    const V = #run selfMoveInfo()
    #assert(V.dst == 6)
    #assert(V.src == 6)
    #assert(V.drops == 0)
    #assert(V.dropTrace == 0)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 0)
}

#test
{
    const V = #run moveRefAssignInfo()
    #assert(V.dst == 24)
    #assert(V.src == 5)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 6)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 1)
}

#test
{
    const V = #run overloadCopyInfo()
    #assert(V.dst == 19)
    #assert(V.src == 9)
    #assert(V.drops == 2)
    #assert(V.dropTrace == 509)
    #assert(V.postCopy == 1)
    #assert(V.postMove == 0)
}

#test
{
    const V = #run overloadMoveInfo()
    #assert(V.dst == 29)
    #assert(V.src == 5)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 5)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 1)
}

#test
{
    const V = #run embeddedCopyAssignInfo()
    #assert(V.dst == 12)
    #assert(V.src == 2)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 1)
    #assert(V.postCopy == 1)
    #assert(V.postMove == 0)
}

#test
{
    const V = #run embeddedMoveAssignInfo()
    #assert(V.dst == 23)
    #assert(V.src == 5)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 7)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 1)
}

#test
{
    const V = #run embeddedOuterCopyAssignInfo()
    #assert(V.dst == 115)
    #assert(V.src == 5)
    #assert(V.drops == 2)
    #assert(V.dropTrace == 9004)
    #assert(V.postCopy == 2)
    #assert(V.postMove == 0)
}

#test
{
    const V = #run embeddedOuterMoveAssignInfo()
    #assert(V.dst == 223)
    #assert(V.src == 5)
    #assert(V.drops == 2)
    #assert(V.dropTrace == 9008)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 2)
}

#test
{
    const V = #run embeddedOuterNoDropCopyAssignInfo()
    #assert(V.dst == 112)
    #assert(V.src == 2)
    #assert(V.drops == 0)
    #assert(V.dropTrace == 0)
    #assert(V.postCopy == 2)
    #assert(V.postMove == 0)
}
