#global private
// This file asserts the RAW '@drop'/'@postcopy'/'@postmove'/'@init' mechanics,
// including reading storage after '@drop': lifecycle safety (use-after-move check +
// poisoning) is disabled for the whole file.
#global #[Swag.Safety(.Lifecycle, false)]

var DropCount: u32 = 0
var DropTrace: s64 = 0
var DropCompactTrace: s64 = 0
var PostCopyCount: u32 = 0
var PostMoveCount: u32 = 0

func resetLifecycleHooks()
{
    DropCount = 0
    DropTrace = 0
    DropCompactTrace = 0
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

struct InitInfo
{
    scalarDefault: s32
    scalarExplicitScaled: s32
    arrayDefaultTrace: s32
    arrayExplicitTrace: s32
    structDefaultTrace: s32
    structExplicitTrace: s32
    structArrayCountTrace: s32
    structArrayWholeTrace: s32
}

struct InitRgb
{
    r: s32 = 1
    g: s32 = 2
    b: s32 = 3
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

struct EmbeddedTrackedArray
{
    inner: [2] Tracked
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

struct DropOnlyTracked
{
    value: s32
}

impl DropOnlyTracked
{
    mtd opDrop()
    {
        DropCount += 1
        DropTrace = DropTrace * 100 + cast(s64) .value
    }
}

struct AutoDropPair
{
    first: DropOnlyTracked
    second: DropOnlyTracked
}

struct AutoDropNested
{
    head: DropOnlyTracked
    pairs: [2] AutoDropPair
    tail: DropOnlyTracked
}

struct AutoDropBranch
{
    head: DropOnlyTracked
    pair: AutoDropPair
}

struct CompactDropTracked
{
    value: s32
}

impl CompactDropTracked
{
    mtd opDrop()
    {
        DropCount += 1
        DropCompactTrace = DropCompactTrace * 10 + cast(s64) .value
    }
}

struct AutoCompactPair
{
    first: CompactDropTracked
    second: CompactDropTracked
}

struct AutoCompactBranch
{
    head: CompactDropTracked
    pair: AutoCompactPair
}

struct IntrinsicLifecycleErr
{
    using base: Swag.BaseError
    code: s32 = 0
}

struct ReceiverLifecycleTracked
{
    value: s32 = 3
}

impl ReceiverLifecycleTracked
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

    mtd reset()
    {
        @init(me, 1)
    }

    mtd touchPostCopy()
    {
        @postcopy(me, 1)
    }

    mtd touchPostMove()
    {
        @postmove(me, 1)
    }

    mtd touchDrop()
    {
        @drop(me, 1)
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

func intrinsicEmbeddedInfo()->IntrinsicInfo
{
    resetLifecycleHooks()
    var a = EmbeddedTracked{Tracked{1}}
    var b = EmbeddedTrackedWithOps{Tracked{2}}
    var c = EmbeddedTrackedArray{[Tracked{3}, Tracked{4}]}
    @postcopy(a)
    @postmove(b)
    @drop(c)
    return {a.inner.value, b.inner.value, c.inner[1].value, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicEmbeddedOuterCopyDropInfo()->IntrinsicInfo
{
    resetLifecycleHooks()
    var a = EmbeddedTrackedWithOps{Tracked{7}}
    @postcopy(a)
    @drop(a)
    return {a.inner.value, 0, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicInitInfo()->InitInfo
{
    var x = 666
    @init(x)

    var y = 666'f32
    @init(y)(3.14)

    var arr = [1, 2]
    @init(&arr, 2)
    let arrDefaultTrace = arr[0] * 10 + arr[1]

    @init(&arr, 2)(555)
    let arrExplicitTrace = arr[0] * 1000 + arr[1]

    var rgb = InitRgb{10, 20, 30}
    @init(rgb)
    let rgbDefaultTrace = rgb.r * 100 + rgb.g * 10 + rgb.b

    @init(rgb)(5, 6, 7)
    let rgbExplicitTrace = rgb.r * 100 + rgb.g * 10 + rgb.b

    var rgbArr: [4] InitRgb
    @init(&rgbArr, 4)(5, 6, 7)
    let rgbArrayCountTrace = rgbArr[3].r * 100 + rgbArr[3].g * 10 + rgbArr[3].b

    @init(rgbArr)(50, 60, 70)
    let rgbArrayWholeTrace = rgbArr[3].r * 10000 + rgbArr[3].g * 100 + rgbArr[3].b

    return {x, cast(s32) (y * 100), arrDefaultTrace, arrExplicitTrace, rgbDefaultTrace, rgbExplicitTrace, rgbArrayCountTrace, rgbArrayWholeTrace}
}

func intrinsicDropThenInitArrayInfo()->s32
{
    var rgb: [4] InitRgb
    @drop(&rgb, 4)
    @init(&rgb, 4)(5, 6, 7)
    return rgb[3].r * 100 + rgb[3].g * 10 + rgb[3].b
}

func intrinsicAutoDropPairInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first: s32 = 0
    {
        var value = AutoDropPair{DropOnlyTracked{1}, DropOnlyTracked{2}}
        first = value.first.value
    }

    return {first, 0, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicAutoDropNestedInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first: s32 = 0
    var last: s32 = 0
    {
        var value = AutoDropNested{DropOnlyTracked{1}, [AutoDropPair{DropOnlyTracked{2}, DropOnlyTracked{3}}, AutoDropPair{DropOnlyTracked{4}, DropOnlyTracked{5}}], DropOnlyTracked{6}}
        first = value.head.value
        last = value.tail.value
    }

    return {first, last, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicAutoDropStructArrayInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first: s32 = 0
    var last: s32 = 0
    {
        var values: [2] AutoDropPair = [AutoDropPair{DropOnlyTracked{7}, DropOnlyTracked{8}}, AutoDropPair{DropOnlyTracked{9}, DropOnlyTracked{10}}]
        first = values[0].first.value
        last = values[1].second.value
    }

    return {first, last, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicAutoDropReturnInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    with var result: retval
    {
        .first = 0
        .second = 0
        .third = 0
        .drops = 0
        .dropTrace = 0
        .postCopy = 0
        .postMove = 0
    }

    defer result.dropTrace = DropTrace
    defer result.drops = DropCount

    {
        var pair = AutoDropPair{DropOnlyTracked{1}, DropOnlyTracked{2}}
        result.first = pair.first.value

        {
            var nested = AutoDropNested{DropOnlyTracked{3}, [AutoDropPair{DropOnlyTracked{4}, DropOnlyTracked{5}}, AutoDropPair{DropOnlyTracked{6}, DropOnlyTracked{7}}], DropOnlyTracked{8}}
            result.second = nested.tail.value
            result.third = nested.pairs[1].second.value
            return result
        }
    }
}

func intrinsicAutoDropErrorImpl() throw
{
    {
        var pair = AutoDropPair{DropOnlyTracked{1}, DropOnlyTracked{2}}

        {
            var nested = AutoDropNested{DropOnlyTracked{3}, [AutoDropPair{DropOnlyTracked{4}, DropOnlyTracked{5}}, AutoDropPair{DropOnlyTracked{6}, DropOnlyTracked{7}}], DropOnlyTracked{8}}
            if pair.first.value == 1 and nested.tail.value == 8 do
                throw IntrinsicLifecycleErr{code: 77}
        }
    }
}

func intrinsicAutoDropErrorInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    with var result: retval
    {
        .first = 0
        .second = 0
        .third = 0
        .drops = 0
        .dropTrace = 0
        .postCopy = 0
        .postMove = 0
    }

    catch intrinsicAutoDropErrorImpl()
    if @err != null
    {
        let err = cast(IntrinsicLifecycleErr) @err
        result.first = err.code
        result.second = 1
    }

    result.drops = DropCount
    result.dropTrace = DropTrace
    return result
}

func intrinsicAutoDropDeferInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    with var result: retval
    {
        .first = 0
        .second = 0
        .third = 0
        .drops = 0
        .dropTrace = 0
        .postCopy = 0
        .postMove = 0
    }

    {
        defer result.first = cast(s32) DropCount
        var pair = AutoDropPair{DropOnlyTracked{1}, DropOnlyTracked{2}}

        {
            defer result.second = cast(s32) DropCount
            var nested = AutoDropNested{DropOnlyTracked{3}, [AutoDropPair{DropOnlyTracked{4}, DropOnlyTracked{5}}, AutoDropPair{DropOnlyTracked{6}, DropOnlyTracked{7}}], DropOnlyTracked{8}}
            result.third = nested.tail.value
        }
    }

    result.drops = DropCount
    result.dropTrace = DropTrace
    return result
}

func intrinsicAutoDropContinueInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first: s32 = 0
    var second: s32 = 0
    var third: s32 = 0
    {
        var outer = DropOnlyTracked{9}
        for i in 2
        {
            var pair = AutoDropPair{DropOnlyTracked{cast(s32) (i * 2 + 1)}, DropOnlyTracked{cast(s32) (i * 2 + 2)}}
            first += pair.first.value
            if i == 0 do
                continue

            var branch = AutoDropBranch{DropOnlyTracked{5}, AutoDropPair{DropOnlyTracked{6}, DropOnlyTracked{7}}}
            second = branch.head.value
            third = outer.value
        }
    }

    return {first, second, third, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicAutoDropBreakScopeInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first: s32 = 0
    var second: s32 = 0
    var third: s32 = 0
    {
        var outer = AutoDropPair{DropOnlyTracked{1}, DropOnlyTracked{2}}
        #scope(Exit)
        {
            var scopeValue = AutoDropBranch{DropOnlyTracked{3}, AutoDropPair{DropOnlyTracked{4}, DropOnlyTracked{5}}}
            first = outer.first.value + scopeValue.head.value

            for i in 3
            {
                var current = AutoDropPair{DropOnlyTracked{6}, DropOnlyTracked{7}}
                second = current.second.value + cast(s32) i
                break to Exit
            }
        }

        third = outer.second.value
    }

    return {first, second, third, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func intrinsicAutoDropSwitchReturnInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    with var result: retval
    {
        .first = 0
        .second = 0
        .third = 0
        .drops = 0
        .dropTrace = 0
        .postCopy = 0
        .postMove = 0
    }

    defer result.dropTrace = DropTrace
    defer result.drops = DropCount

    {
        var outer = AutoDropPair{DropOnlyTracked{1}, DropOnlyTracked{2}}
        switch 2
        {
            case 1:
                result.first = -1

            case 2:
                var active = AutoDropBranch{DropOnlyTracked{6}, AutoDropPair{DropOnlyTracked{7}, DropOnlyTracked{8}}}
                result.first = outer.second.value
                result.second = active.head.value
                result.third = active.pair.first.value
                return result

            default:
                result.third = -2
        }
    }

    return result
}

func intrinsicAutoDropCatchResumeImpl(code: s32) throw
{
    var branch = AutoCompactBranch{CompactDropTracked{3}, AutoCompactPair{CompactDropTracked{4}, CompactDropTracked{5}}}
    if branch.head.value == 3 do
        throw IntrinsicLifecycleErr{code: code}
}

func intrinsicAutoDropCatchResumeInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first: s32 = 0
    var second: s32 = 0
    var third: s32 = 0
    {
        var outer = AutoCompactPair{CompactDropTracked{8}, CompactDropTracked{9}}
        catch intrinsicAutoDropCatchResumeImpl(55)
        if @err != null
        {
            let err = cast(IntrinsicLifecycleErr) @err
            first = err.code
            second = outer.second.value
            third = 1
        }
    }

    return {first, second, third, DropCount, DropCompactTrace, PostCopyCount, PostMoveCount}
}

func intrinsicAutoDropTryCatchLoopStep(base: s32)->s32 throw
{
    var branch = AutoCompactBranch{CompactDropTracked{base}, AutoCompactPair{CompactDropTracked{base + 1}, CompactDropTracked{base + 2}}}
    if base == 1 do
        throw IntrinsicLifecycleErr{code: 66}
    return branch.pair.first.value
}

func intrinsicAutoDropTryCatchLoopInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first: s32 = 0
    var second: s32 = 0
    var third: s32 = 0
    {
        var outer = CompactDropTracked{9}
        for i in 2
        {
            let base = cast(s32) (i * 3 + 1)
            let value: s32 = trycatch intrinsicAutoDropTryCatchLoopStep(base)
            if value == 0
            {
                second += 1
                continue
            }

            first += value
            var pair = AutoCompactPair{CompactDropTracked{7}, CompactDropTracked{8}}
            third = pair.second.value + outer.value
        }
    }

    return {first, second, third, DropCount, DropCompactTrace, PostCopyCount, PostMoveCount}
}

func intrinsicAutoDropSwitchFallthroughInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    with var result: retval
    {
        .first = 0
        .second = 0
        .third = 0
        .drops = 0
        .dropTrace = 0
        .postCopy = 0
        .postMove = 0
    }

    defer result.dropTrace = DropCompactTrace
    defer result.drops = DropCount

    {
        var outer = AutoCompactPair{CompactDropTracked{6}, CompactDropTracked{7}}
        switch 1
        {
            case 1:
                {
                    var firstCase = AutoCompactPair{CompactDropTracked{1}, CompactDropTracked{2}}
                    result.first = firstCase.first.value
                }
                fallthrough

            case 2:
                {
                    var active = AutoCompactBranch{CompactDropTracked{3}, AutoCompactPair{CompactDropTracked{4}, CompactDropTracked{5}}}
                    result.second = active.head.value
                    result.third = outer.second.value
                    return result
                }

            default:
                result.third = -1
        }
    }

    return result
}

func intrinsicAutoDropIfVarReturnInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    with var result: retval
    {
        .first = 0
        .second = 0
        .third = 0
        .drops = 0
        .dropTrace = 0
        .postCopy = 0
        .postMove = 0
    }

    defer result.dropTrace = DropCompactTrace
    defer result.drops = DropCount

    {
        var outer = CompactDropTracked{1}
        if var flag = 1 where flag == 1
        {
            var branch = AutoCompactBranch{CompactDropTracked{2}, AutoCompactPair{CompactDropTracked{3}, CompactDropTracked{4}}}
            var inner = AutoCompactPair{CompactDropTracked{5}, CompactDropTracked{6}}
            result.first = flag + outer.value
            result.second = branch.pair.first.value
            result.third = inner.second.value
            return result
        }
    }

    result.third = -1
    return result
}

func intrinsicAutoDropIfVarElseInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first: s32 = 0
    var second: s32 = 0
    var third: s32 = 0
    {
        var outer = CompactDropTracked{9}
        if var flag = 1 where false
        {
            first = -1
        }
        else
        {
            var active = AutoCompactBranch{CompactDropTracked{1}, AutoCompactPair{CompactDropTracked{2}, CompactDropTracked{3}}}
            first = flag + 5
            second = active.head.value
            third = outer.value
        }
    }

    return {first, second, third, DropCount, DropCompactTrace, PostCopyCount, PostMoveCount}
}

func intrinsicAutoDropWithVarReturnInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    with var result: retval
    {
        .first = 0
        .second = 0
        .third = 0
        .drops = 0
        .dropTrace = 0
        .postCopy = 0
        .postMove = 0
    }

    defer result.dropTrace = DropCompactTrace
    defer result.drops = DropCount

    with var pair = AutoCompactPair{CompactDropTracked{7}, CompactDropTracked{8}}
    {
        var active = AutoCompactBranch{CompactDropTracked{4}, AutoCompactPair{CompactDropTracked{5}, CompactDropTracked{6}}}
        result.first = pair.first.value
        result.second = active.head.value
        result.third = pair.second.value
        return result
    }

    result.third = -1
    return result
}

func intrinsicAutoDropShadowInfo()->IntrinsicInfo
{
    resetLifecycleHooks()

    var first: s32 = 0
    var second: s32 = 0
    var third: s32 = 0
    {
        var value = CompactDropTracked{9}
        first = value.value

        {
            var value = AutoCompactBranch{CompactDropTracked{1}, AutoCompactPair{CompactDropTracked{2}, CompactDropTracked{3}}}
            second = value.pair.first.value
        }

        var pair = AutoCompactPair{CompactDropTracked{4}, CompactDropTracked{5}}
        third = pair.second.value
    }

    return {first, second, third, DropCount, DropCompactTrace, PostCopyCount, PostMoveCount}
}

func intrinsicReceiverLifecycleInfo()->IntrinsicInfo
{
    resetLifecycleHooks()
    var value = ReceiverLifecycleTracked{7}
    value.touchPostCopy()
    value.touchPostMove()
    value.touchDrop()
    value.reset()
    return {value.value, 0, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
}

func semaTest001()
{
    const V = #run intrinsicSingleInfo()
    #assert(V.first == 11)
    #assert(V.second == 22)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 11)
    #assert(V.postCopy == 1)
    #assert(V.postMove == 1)
}

func semaTest002()
{
    const V = #run intrinsicArrayWholeInfo()
    #assert(V.first == 13)
    #assert(V.second == 14)
    #assert(V.drops == 2)
    #assert(V.dropTrace == 1314)
    #assert(V.postCopy == 2)
    #assert(V.postMove == 0)
}

func semaTest003()
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

func semaTest004()
{
    const V = #run intrinsicEmbeddedInfo()
    #assert(V.first == 11)
    #assert(V.second == 222)
    #assert(V.third == 4)
    #assert(V.drops == 2)
    #assert(V.dropTrace == 304)
    #assert(V.postCopy == 1)
    #assert(V.postMove == 2)
}

func semaTest005()
{
    const V = #run intrinsicEmbeddedOuterCopyDropInfo()
    #assert(V.first == 117)
    #assert(V.drops == 2)
    #assert(V.dropTrace == 9117)
    #assert(V.postCopy == 2)
    #assert(V.postMove == 0)
}

func semaTest006()
{
    const V = #run intrinsicInitInfo()
    #assert(V.scalarDefault == 0)
    #assert(V.scalarExplicitScaled == 314)
    #assert(V.arrayDefaultTrace == 0)
    #assert(V.arrayExplicitTrace == 555555)
    #assert(V.structDefaultTrace == 123)
    #assert(V.structExplicitTrace == 567)
    #assert(V.structArrayCountTrace == 567)
    #assert(V.structArrayWholeTrace == 506070)
}

func semaTest007()
{
    const V = #run intrinsicDropThenInitArrayInfo()
    #assert(V == 567)
}

func semaTest008()
{
    const V = #run intrinsicAutoDropPairInfo()
    #assert(V.first == 1)
    #assert(V.drops == 2)
    #assert(V.dropTrace == 201)
}

func semaTest009()
{
    const V = #run intrinsicAutoDropNestedInfo()
    #assert(V.first == 1)
    #assert(V.second == 6)
    #assert(V.drops == 6)
    #assert(V.dropTrace == 60302050401)
}

func semaTest010()
{
    const V = #run intrinsicAutoDropStructArrayInfo()
    #assert(V.first == 7)
    #assert(V.second == 10)
    #assert(V.drops == 4)
    #assert(V.dropTrace == 8071009)
}

func semaTest011()
{
    const V = #run intrinsicAutoDropReturnInfo()
    #assert(V.first == 1)
    #assert(V.second == 8)
    #assert(V.third == 7)
    #assert(V.drops == 8)
    #assert(V.dropTrace == 805040706030201)
}

func semaTest012()
{
    const V = #run intrinsicAutoDropErrorInfo()
    #assert(V.first == 77)
    #assert(V.second == 1)
    #assert(V.drops == 8)
    #assert(V.dropTrace == 805040706030201)
}

func semaTest013()
{
    const V = #run intrinsicAutoDropDeferInfo()
    #assert(V.first == 8)
    #assert(V.second == 6)
    #assert(V.third == 8)
    #assert(V.drops == 8)
    #assert(V.dropTrace == 805040706030201)
}

func semaTest014()
{
    const V = #run intrinsicAutoDropContinueInfo()
    #assert(V.first == 4)
    #assert(V.second == 5)
    #assert(V.third == 9)
    #assert(V.drops == 8)
    #assert(V.dropTrace == 201070605040309)
}

func semaTest015()
{
    const V = #run intrinsicAutoDropBreakScopeInfo()
    #assert(V.first == 4)
    #assert(V.second == 7)
    #assert(V.third == 2)
    #assert(V.drops == 7)
    #assert(V.dropTrace == 7060504030201)
}

func semaTest016()
{
    const V = #run intrinsicAutoDropSwitchReturnInfo()
    #assert(V.first == 2)
    #assert(V.second == 6)
    #assert(V.third == 7)
    #assert(V.drops == 5)
    #assert(V.dropTrace == 807060201)
}

func semaTest017()
{
    const V = #run intrinsicAutoDropCatchResumeInfo()
    #assert(V.first == 55)
    #assert(V.second == 9)
    #assert(V.third == 1)
    #assert(V.drops == 5)
    #assert(V.dropTrace == 54398)
}

func semaTest018()
{
    const V = #run intrinsicAutoDropTryCatchLoopInfo()
    #assert(V.first == 5)
    #assert(V.second == 1)
    #assert(V.third == 17)
    #assert(V.drops == 9)
    #assert(V.dropTrace == 321654879)
}

func semaTest019()
{
    const V = #run intrinsicAutoDropSwitchFallthroughInfo()
    #assert(V.first == 1)
    #assert(V.second == 3)
    #assert(V.third == 7)
    #assert(V.drops == 7)
    #assert(V.dropTrace == 2154376)
}

func semaTest020()
{
    const V = #run intrinsicAutoDropIfVarReturnInfo()
    #assert(V.first == 2)
    #assert(V.second == 3)
    #assert(V.third == 6)
    #assert(V.drops == 6)
    #assert(V.dropTrace == 654321)
}

func semaTest021()
{
    const V = #run intrinsicAutoDropIfVarElseInfo()
    #assert(V.first == 6)
    #assert(V.second == 1)
    #assert(V.third == 9)
    #assert(V.drops == 4)
    #assert(V.dropTrace == 3219)
}

func semaTest022()
{
    const V = #run intrinsicAutoDropWithVarReturnInfo()
    #assert(V.first == 7)
    #assert(V.second == 4)
    #assert(V.third == 8)
    #assert(V.drops == 5)
    #assert(V.dropTrace == 65487)
}

func semaTest023()
{
    const V = #run intrinsicAutoDropShadowInfo()
    #assert(V.first == 9)
    #assert(V.second == 2)
    #assert(V.third == 5)
    #assert(V.drops == 6)
    #assert(V.dropTrace == 321549)
}

func semaTest024()
{
    const V = #run intrinsicReceiverLifecycleInfo()
    #assert(V.first == 3)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 37)
    #assert(V.postCopy == 1)
    #assert(V.postMove == 1)
}
