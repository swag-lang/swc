#global private

// A value that points into its own storage stays valid wherever a literal places it. A literal
// nested in another one is built in a temporary and moved into its element, so its move hook
// has to run there; a literal folded to a constant owns nothing and runs no hook at all.

struct SelfBuf
{
    buffer:  [*] u8?
    count:   u32
    storage: [4] u8
}

impl SelfBuf
{
    mtd opPostMove()
    {
        if buffer do
            buffer = cast([*] u8, &storage[0])
    }

    mtd opPostCopy()
    {
        if buffer do
            buffer = cast([*] u8, &storage[0])
    }

    #[Swag.NoInline]
    mtd const valid()->bool => buffer == cast([*] u8, &storage[0])
}

#[Swag.NoInline]
func makeSelfBuf(a, b: u8, count: u32)->SelfBuf
{
    var result: retval
    result.storage = [a, b, 0, 0]
    result.buffer  = cast([*] u8, &result.storage[0])
    result.count   = count
    return result
}

struct Wrapper
{
    prev: SelfBuf
}

func makeWrapper()->Wrapper => {prev: makeSelfBuf(1, 2, 2)}

// Calls that return a self-referencing value need relocation even without a drop hook.
#test
{
    let wrapper = Wrapper{prev: makeSelfBuf(1, 2, 2)}
    Swag.assert(wrapper.prev.valid())
    let projected = makeWrapper().prev
    Swag.assert(projected.valid())
}

#test
{
    var direct = makeSelfBuf(1, 2, 2)
    Swag.assert(direct.valid())

    let single = Wrapper{prev: direct}
    Swag.assert(single.prev.valid())

    let wrappers = [Wrapper{prev: direct}, Wrapper{prev: direct}]
    Swag.assert(wrappers[0].prev.valid() and wrappers[1].prev.valid())

    for wrapper in wrappers do
        Swag.assert(wrapper.prev.valid())
}

var g_ConstantMoves: s32

struct Counted
{
    value: s64
}

impl Counted
{
    mtd opPostMove()
    {
        g_ConstantMoves += 1
    }
}

#[Swag.NoInline]
func makeCounted()->Counted
{
    return Counted{3}
}

// Whether the call runs or is folded into its constant, the caller receives the value alone.
#test
{
    g_ConstantMoves = 0
    let counted = makeCounted()
    Swag.assert(counted.value == 3)
    Swag.assert(g_ConstantMoves == 0)
}
