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

#[Swag.Overload]
func assignTracked(dst: &Tracked, src: &&Tracked)
{
    dst = #move src
}

#[Swag.Overload]
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
    let v = moveRawInfo()
    @assert(v.dst == 23)
    @assert(v.src == 3)
    @assert(v.drops == 1)
    @assert(v.dropTrace == 8)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 1)
}

#test
{
    let v = noDropMoveRawInfo()
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
    @assert(v.drops == 2)
    @assert(v.dropTrace == 509)
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
