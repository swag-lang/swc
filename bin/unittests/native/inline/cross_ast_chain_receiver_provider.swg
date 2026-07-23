#global namespace InlineChain

// Chained cross-Ast inline regression: `me.slab[i].method()` where BOTH the `opIndex` (returning a
// reference) and the element method are `#[Inline]`, and the chain's base (`.slab`) is a method
// auto-member. The inner inline-`opIndex` receiver is a caller expression (`me.slab`) materialized
// into the callee inline body; it must stay resolved against the CALLER's `me` rather than
// re-resolve its `.` marker in the callee inline frame (which used to stall: "unknown symbol '.'").
// Mirrors std gui richedit `.lines[i].isVisible()`. The provider lives in another file (its own
// Ast) so the inline crosses an Ast boundary.

public struct Cell
{
    flag: bool
    n:    s32
}

impl Cell
{
    #[Swag.Inline]
    mtd isOn()->bool
    {
        return .flag
    }

    #[Swag.Inline]
    mtd turnOn()
    {
        .flag = true
        .n    += 10
    }
}

public struct(T) Slab
{
    cells: [4] T
}

impl Slab
{
    #[Swag.Inline]
    mtd opIndex(i: u64)->&T
    {
        return &.cells[i]
    }
}
