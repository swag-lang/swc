#global private

// A strict alias of a POINTER names the indirection, not the pointee's members: a
// member reached through such a receiver keeps its own type. Re-typing it as the alias
// would make an arithmetic body compare two pointers.

struct StrictAliasVec2
{
    x: s32
    y: s32
}

#[Swag.Strict]
alias StrictAliasVec2Ptr = *StrictAliasVec2

impl StrictAliasVec2
{
    mtd length2()->s32 => .x * .x + .y * .y

    mtd negate()
    {
        .x = -.x
        .y = -.y
    }
}

// A method called through a strict-alias receiver reads and writes the pointee.
#test
{
    var v: StrictAliasVec2 = {x: 6, y: 8}
    let p = cast(StrictAliasVec2Ptr) &v

    #assert(#typeof(p) == StrictAliasVec2Ptr)
    Swag.assert(p.length2() == 100)

    p.negate()
    Swag.assert(v.x == -6)
    Swag.assert(v.y == -8)
}

// A member read through the strict-alias receiver keeps the field's own type.
#test
{
    var v: StrictAliasVec2 = {x: 3, y: 4}
    let p = cast(StrictAliasVec2Ptr) &v

    #assert(#typeof(p.x) == s32)
    Swag.assert(p.x * p.y == 12)
}
