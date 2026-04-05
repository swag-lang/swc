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

struct IntrinsicInfo
{
    first: s32
    second: s32
    third: s32
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

func intrinsicSingleInfo()->IntrinsicInfo
{
    resetLifecycleHooks()
    var a = Tracked{1}
    var b = Tracked{2}
    @postcopy(a)
    @postmove(b)
    @drop(a)
    return {a.value, b.value, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicArrayWholeInfo()->IntrinsicInfo
{
    resetLifecycleHooks()
    var arr: [2] Tracked = [Tracked{3}, Tracked{4}]
    @postcopy(arr)
    @drop(arr)
    return {arr[0].value, arr[1].value, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicArrayCountInfo()->IntrinsicInfo
{
    resetLifecycleHooks()
    var arr: [3] Tracked = [Tracked{1}, Tracked{2}, Tracked{3}]
    var count: u64 = 2
    @postmove(&arr[0], count)
    @drop(&arr[0], count)
    return {arr[0].value, arr[1].value, arr[2].value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

#test
{
    const V = #run intrinsicSingleInfo()
    #assert(V.first == 11)
    #assert(V.second == 22)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 11)
    #assert(V.postCopy == 1)
    #assert(V.postMove == 1)
}

#test
{
    const V = #run intrinsicArrayWholeInfo()
    #assert(V.first == 13)
    #assert(V.second == 14)
    #assert(V.drops == 2)
    #assert(V.dropTrace == 1314)
    #assert(V.postCopy == 2)
    #assert(V.postMove == 0)
}

#test
{
    const V = #run intrinsicArrayCountInfo()
    #assert(V.first == 21)
    #assert(V.second == 22)
    #assert(V.third == 3)
    #assert(V.drops == 2)
    #assert(V.dropTrace == 2122)
    #assert(V.postCopy == 0)
    #assert(V.postMove == 2)
}
