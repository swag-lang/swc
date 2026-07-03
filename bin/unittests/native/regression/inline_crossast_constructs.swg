#global private

// Cross-Ast inline of a cast expression.
//
// An #[Inline] body containing a cast must materialize correctly across an Ast boundary.
// Instantiating a generic clones the method into its own Ast, so inlining it at the call site is
// a genuine cross-Ast inline. The asserts verify the materialized cast computes correctly.

struct(T) CrossAstCastProbe
{
    val: T
}

impl CrossAstCastProbe
{
    // CastExpr (+ auto-member receiver) in a cross-Ast inlined body.
    #[Swag.Inline]
    mtd asS32()->s32
    {
        return cast(s32) .val
    }

    #[Swag.Inline]
    mtd doubledAsU8()->u8
    {
        return cast(u8) (.val + .val)
    }
}

#test
{
    var probe: CrossAstCastProbe'u64
    probe.val = 42
    @assert(probe.asS32() == 42)
    @assert(probe.doubledAsU8() == 84)

    var probe2: CrossAstCastProbe'f64
    probe2.val = 7.0
    @assert(probe2.asS32() == 7)
}
