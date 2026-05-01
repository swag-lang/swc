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

enum IntrinsicStrictEnum: u32
{
    Zero = 0,
    A = 1,
    B = 2,
}

#[Swag.Strict]
alias IntrinsicStrictEnumAlias = IntrinsicStrictEnum

#[Swag.Strict]
alias IntrinsicStrictIntAlias = s32

#[Swag.Strict]
alias IntrinsicStrictFloatAlias = f32

#[Swag.Strict]
alias IntrinsicStrictS32Ptr = *s32

#[Swag.Strict]
alias IntrinsicStrictStringAlias = string

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

#[Swag.Strict]
alias LifecycleStrictTrackedPtr = *Tracked

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

func intrinsicStrictAliasPointerCountInfo()->IntrinsicInfo
{
    resetLifecycleHooks()
    var arr: [2] Tracked = [Tracked{5}, Tracked{6}]
    let ptr = cast(LifecycleStrictTrackedPtr) &arr[0]
    @postmove(ptr, 2)
    @drop(ptr, 2)
    return {arr[0].value, arr[1].value, 0, DropCount, DropTrace, PostCopyCount, PostMoveCount}
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

func intrinsicInitStrictEnumInfo()->bool
{
    var value: IntrinsicStrictEnumAlias
    @init(value)(cast(IntrinsicStrictEnumAlias) IntrinsicStrictEnum.B)

    var values: [3] IntrinsicStrictEnumAlias
    @init(&values, 3)(cast(IntrinsicStrictEnumAlias) IntrinsicStrictEnum.A)

    return value == cast(IntrinsicStrictEnumAlias) IntrinsicStrictEnum.B and values[0] == cast(IntrinsicStrictEnumAlias) IntrinsicStrictEnum.A and values[2] == cast(IntrinsicStrictEnumAlias) IntrinsicStrictEnum.A
}

func intrinsicInitStrictIntInfo()->bool
{
    var value: IntrinsicStrictIntAlias
    @init(value)(cast(IntrinsicStrictIntAlias) 42)

    var values: [3] IntrinsicStrictIntAlias
    @init(&values, 3)(cast(IntrinsicStrictIntAlias) 7)

    return value == cast(IntrinsicStrictIntAlias) 42 and values[0] == cast(IntrinsicStrictIntAlias) 7 and values[2] == cast(IntrinsicStrictIntAlias) 7
}

func intrinsicInitStrictFloatInfo()->bool
{
    var value: IntrinsicStrictFloatAlias
    @init(value)(cast(IntrinsicStrictFloatAlias) 1.5)

    var values: [3] IntrinsicStrictFloatAlias
    @init(&values, 3)(cast(IntrinsicStrictFloatAlias) 2.5)

    return value == cast(IntrinsicStrictFloatAlias) 1.5 and values[0] == cast(IntrinsicStrictFloatAlias) 2.5 and values[2] == cast(IntrinsicStrictFloatAlias) 2.5
}

func intrinsicInitStrictPointerInfo()->bool
{
    var first: s32 = 42
    var second: s32 = 7

    var value: IntrinsicStrictS32Ptr
    @init(&value)(cast(IntrinsicStrictS32Ptr) &first)

    var values: [2] IntrinsicStrictS32Ptr
    @init(&values, 2)(cast(IntrinsicStrictS32Ptr) &second)

    return dref value == 42 and dref values[0] == 7 and dref values[1] == 7
}

func intrinsicInitStrictStringInfo()->bool
{
    var value: IntrinsicStrictStringAlias
    @init(&value)(cast(IntrinsicStrictStringAlias) "hello")

    var empty: IntrinsicStrictStringAlias
    @init(&empty)

    var values: [2] IntrinsicStrictStringAlias
    @init(&values, 2)(cast(IntrinsicStrictStringAlias) "world")

    return cast(string) value == "hello" and cast(string) empty == "" and cast(string) values[0] == "world" and cast(string) values[1] == "world"
}

func makeIntrinsicRunStrictIntArray()->[2] IntrinsicStrictIntAlias
{
    return [cast(IntrinsicStrictIntAlias) 11, cast(IntrinsicStrictIntAlias) 13]
}

func makeIntrinsicRunStrictFloatArray()->[2] IntrinsicStrictFloatAlias
{
    return [cast(IntrinsicStrictFloatAlias) 1.25, cast(IntrinsicStrictFloatAlias) 2.5]
}

const IntrinsicRunStrictInts: [2] IntrinsicStrictIntAlias = #run makeIntrinsicRunStrictIntArray()
const IntrinsicRunStrictFloats: [2] IntrinsicStrictFloatAlias = #run makeIntrinsicRunStrictFloatArray()

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

#test
{
    let v = intrinsicSingleInfo()
    @assert(v.first == 11)
    @assert(v.second == 22)
    @assert(v.drops == 1)
    @assert(v.dropTrace == 11)
    @assert(v.postCopy == 1)
    @assert(v.postMove == 1)
}

#test
{
    let v = intrinsicArrayWholeInfo()
    @assert(v.first == 13)
    @assert(v.second == 14)
    @assert(v.drops == 2)
    @assert(v.dropTrace == 1314)
    @assert(v.postCopy == 2)
    @assert(v.postMove == 0)
}

#test
{
    let v = intrinsicArrayCountInfo()
    @assert(v.first == 21)
    @assert(v.second == 22)
    @assert(v.third == 3)
    @assert(v.drops == 2)
    @assert(v.dropTrace == 2122)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 2)
}

#test
{
    let v = intrinsicStrictAliasPointerCountInfo()
    @assert(v.first == 25)
    @assert(v.second == 26)
    @assert(v.drops == 2)
    @assert(v.dropTrace == 2526)
    @assert(v.postCopy == 0)
    @assert(v.postMove == 2)
}

#test
{
    let v = intrinsicEmbeddedInfo()
    @assert(v.first == 11)
    @assert(v.second == 222)
    @assert(v.third == 4)
    @assert(v.drops == 2)
    @assert(v.dropTrace == 304)
    @assert(v.postCopy == 1)
    @assert(v.postMove == 2)
}

#test
{
    let v = intrinsicEmbeddedOuterCopyDropInfo()
    @assert(v.first == 117)
    @assert(v.drops == 2)
    @assert(v.dropTrace == 9117)
    @assert(v.postCopy == 2)
    @assert(v.postMove == 0)
}

#test
{
    let v = intrinsicInitInfo()
    @assert(v.scalarDefault == 0)
    @assert(v.scalarExplicitScaled == 314)
    @assert(v.arrayDefaultTrace == 0)
    @assert(v.arrayExplicitTrace == 555555)
    @assert(v.structDefaultTrace == 123)
    @assert(v.structExplicitTrace == 567)
    @assert(v.structArrayCountTrace == 567)
    @assert(v.structArrayWholeTrace == 506070)
}

#test
{
    let v = intrinsicDropThenInitArrayInfo()
    @assert(v == 567)
}

#test
{
    @assert(intrinsicInitStrictEnumInfo())
    @assert(intrinsicInitStrictIntInfo())
    @assert(intrinsicInitStrictFloatInfo())
    @assert(intrinsicInitStrictPointerInfo())
    @assert(intrinsicInitStrictStringInfo())
    @assert(IntrinsicRunStrictInts[0] == cast(IntrinsicStrictIntAlias) 11)
    @assert(IntrinsicRunStrictInts[1] == cast(IntrinsicStrictIntAlias) 13)
    @assert(IntrinsicRunStrictFloats[0] == cast(IntrinsicStrictFloatAlias) 1.25)
    @assert(IntrinsicRunStrictFloats[1] == cast(IntrinsicStrictFloatAlias) 2.5)
}

#test
{
    let v = intrinsicReceiverLifecycleInfo()
    @assert(v.first == 3)
    @assert(v.drops == 1)
    @assert(v.dropTrace == 37)
    @assert(v.postCopy == 1)
    @assert(v.postMove == 1)
}
