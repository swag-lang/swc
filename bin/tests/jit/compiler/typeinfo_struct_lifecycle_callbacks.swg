#global fileprivate
using Swag

var DropCount: s32
var PostCopyCount: s32
var PostMoveCount: s32

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

func resetCounts()
{
    DropCount = 0
    PostCopyCount = 0
    PostMoveCount = 0
}

func runDrop(type: typeinfo, value: *void)
{
    let info = cast(const *Swag.TypeInfoStruct) type
    info.opDrop(value)
}

func runPostCopy(type: typeinfo, value: *void)
{
    let info = cast(const *Swag.TypeInfoStruct) type
    info.opPostCopy(value)
}

func runPostMove(type: typeinfo, value: *void)
{
    let info = cast(const *Swag.TypeInfoStruct) type
    info.opPostMove(value)
}

func typeinfoDropWorks()->bool
{
    resetCounts()

    let type = #typeof(LifecycleProbe)
    var value = LifecycleProbe{}
    runDrop(type, &value)
    return DropCount == 1
}

func typeinfoCopyWorks()->bool
{
    resetCounts()

    var src = LifecycleProbe{value: 5}
    var dst = LifecycleProbe{}
    let type = #typeof(LifecycleProbe)
    dst.value = src.value
    runPostCopy(type, &dst)
    return PostCopyCount == 1 and dst.value == 15
}

func typeinfoMoveWorks()->bool
{
    resetCounts()

    let type = #typeof(LifecycleProbe)
    var value = LifecycleProbe{value: 7}
    runPostMove(type, &value)
    return PostMoveCount == 1 and value.value == 107
}

#test
{
    @assert(typeinfoDropWorks())
    @assert(typeinfoCopyWorks())
    @assert(typeinfoMoveWorks())
}
