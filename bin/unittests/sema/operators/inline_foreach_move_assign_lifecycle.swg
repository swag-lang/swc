#global private

var InlineForeachMoveDropCount: u32 = 0
var InlineForeachMoveDropTrace: s64 = 0
var InlineForeachMovePostMoveCount: u32 = 0

func resetInlineForeachMoveLifecycleHooks()
{
    InlineForeachMoveDropCount = 0
    InlineForeachMoveDropTrace = 0
    InlineForeachMovePostMoveCount = 0
}

struct InlineForeachMoveInfo
{
    dst: s32
    src: s32
    drops: u32
    dropTrace: s64
    postMove: u32
}

struct InlineForeachMoveTracked
{
    value: s32 = 5
}

impl InlineForeachMoveTracked
{
    mtd opDrop()
    {
        InlineForeachMoveDropCount += 1
        InlineForeachMoveDropTrace = InlineForeachMoveDropTrace * 100 + cast(s64) .value
    }

    mtd opPostMove()
    {
        InlineForeachMovePostMoveCount += 1
        .value += 20
    }
}

struct InlineForeachMoveValues
{
    item: InlineForeachMoveTracked
}

impl InlineForeachMoveValues
{
    #[Macro]
    func(ptr: bool, back: bool) opVisit(me, stmt: #code(item, index))
    {
        #if ptr do
            #inject(stmt, item = &me.item, index = 0)
        #else do
            #inject(stmt, item = cast(&InlineForeachMoveTracked) &me.item, index = 0)
    }
}

#[Swag.Inline]
func inlineForeachMoveAssign(dst: &InlineForeachMoveTracked, src: #move InlineForeachMoveTracked)
{
    dst = #move src
}

func inlineForeachMoveInfo()->InlineForeachMoveInfo
{
    var dst: InlineForeachMoveTracked
    var values = InlineForeachMoveValues{InlineForeachMoveTracked{9}}
    resetInlineForeachMoveLifecycleHooks()
    foreach value in values do
        inlineForeachMoveAssign(&dst, #move value)
    return {dst.value, values.item.value, InlineForeachMoveDropCount, InlineForeachMoveDropTrace, InlineForeachMovePostMoveCount}
}

func semaTest001()
{
    const V = #run inlineForeachMoveInfo()
    #assert(V.dst == 29)
    #assert(V.src == 5)
    #assert(V.drops == 1)
    #assert(V.dropTrace == 5)
    #assert(V.postMove == 1)
}
