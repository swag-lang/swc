#global fileprivate

struct(T, Count: s32) Sample
{
    values: [Count] T
}

struct(A, B) Pair
{
    first: A
    second: B
}

struct(A, B, C) Triple
{
    first: A
    second: B
    third: C
}

struct(A, B, Left: s32, Right: s32) IndexedPair
{
    first: A
    second: B
    total: s32
}

struct(A, B, C, Left: s32, Right: s32) IndexedTriple
{
    first: A
    second: B
    third: C
    total: s32
}

impl Sample
{
    func(var U) pairWith(const me, other: U)->Pair'(T, U)
    {
        return {first: me.values[0], second: other}
    }

    func(var U, var V) makeTriple(const me, other: U, tail: V)->Triple'(T, U, V)
    {
        return {first: me.values[0], second: other, third: tail}
    }

    func(const Left: s32, const Right: s32) pickPair(const me)->IndexedPair'(T, T, Left, Right)
    {
        return {first: me.values[Left], second: me.values[Right], total: Left + Right}
    }

    func(var U, var V, const Left: s32, const Right: s32) makeIndexedTriple(const me, other: U, tail: V)->IndexedTriple'(T, U, V, Left, Right)
    {
        return {first: me.values[Left], second: other, third: tail, total: Left + Right}
    }
}

#test
{
    let sample: Sample'(s32, 4)

    let pair = sample.pairWith'(string)("ten")
    let triple = sample.makeTriple'(u8, bool)(9'u8, true)
    let picked = sample.pickPair'(1, 3)()
    let mixed = sample.makeIndexedTriple'(u16, string, 0, 2)(7'u16, "done")

    #assert(#typeof(pair.first) == s32)
    #assert(#typeof(pair.second) == string)
    #assert(#typeof(triple.first) == s32)
    #assert(#typeof(triple.second) == u8)
    #assert(#typeof(triple.third) == bool)
    #assert(#typeof(picked) == IndexedPair'(s32, s32, 1, 3))
    #assert(#typeof(picked.first) == s32)
    #assert(#typeof(picked.second) == s32)
    #assert(#typeof(mixed) == IndexedTriple'(s32, u16, string, 0, 2))
    #assert(#typeof(mixed.first) == s32)
    #assert(#typeof(mixed.second) == u16)
    #assert(#typeof(mixed.third) == string)
}

#test
{
    let sample: Sample'(s32, 2)
    sample.pairWith'(10)(20) // swc-expected-error {{sema_err_not_type}}
}

#test
{
    let sample: Sample'(s32, 2)
    var idx = 1
    sample.pickPair'(idx, 0)() // swc-expected-error {{sema_err_expr_not_const}}
}
