#global fileprivate

// @bug Generic methods declared inside an impl of a generic struct are parsed,
// @bug but sema does not bind method generic parameters or const generic values.
// @bug Uncomment this file content when that support lands.
//
// struct(T, Count: s32) Sample
// {
//     values: [Count] T
// }
//
// struct(A, B) Pair
// {
//     first: A
//     second: B
// }
//
// struct(A, B, C) Triple
// {
//     first: A
//     second: B
//     third: C
// }
//
// struct(A, B, Left: s32, Right: s32) IndexedPair
// {
//     first: A
//     second: B
//     total: s32
// }
//
// struct(A, B, C, Left: s32, Right: s32) IndexedTriple
// {
//     first: A
//     second: B
//     third: C
//     total: s32
// }
//
// impl Sample
// {
//     func(var U) pairWith(me, other: U)->Pair'(T, U)
//     {
//         return {first: me.values[0], second: other}
//     }
//
//     func(var U, var V) makeTriple(me, other: U, tail: V)->Triple'(T, U, V)
//     {
//         return {first: me.values[0], second: other, third: tail}
//     }
//
//     func(const Left: s32, const Right: s32) pickPair(me)->IndexedPair'(T, T, Left, Right)
//     {
//         return {first: me.values[Left], second: me.values[Right], total: Left + Right}
//     }
//
//     func(var U, var V, const Left: s32, const Right: s32) makeIndexedTriple(me, other: U, tail: V)->IndexedTriple'(T, U, V, Left, Right)
//     {
//         return {first: me.values[Left], second: other, third: tail, total: Left + Right}
//     }
// }
//
// #test
// {
//     let sample: Sample'(s32, 4)
//
//     let pair = sample.pairWith'(string)("ten")
//     let triple = sample.makeTriple'(u8, bool)(9'u8, true)
//     let picked = sample.pickPair'(1, 3)()
//     let mixed = sample.makeIndexedTriple'(u16, string, 0, 2)(7'u16, "done")
//
//     #assert(#typeof(pair.first) == s32)
//     #assert(#typeof(pair.second) == string)
//     #assert(#typeof(triple.first) == s32)
//     #assert(#typeof(triple.second) == u8)
//     #assert(#typeof(triple.third) == bool)
//     #assert(#typeof(picked.first) == s32)
//     #assert(#typeof(picked.second) == s32)
//     #assert(#typeof(mixed.first) == s32)
//     #assert(#typeof(mixed.second) == u16)
//     #assert(#typeof(mixed.third) == string)
//     #assert(picked.total == 4)
//     #assert(mixed.total == 2)
// }
//
// #test
// {
//     let sample: Sample'(s32, 2)
//     // @bug Expected sema_err_not_type once generic method sema works.
//     sample.pairWith'(10)(20)
// }
//
// #test
// {
//     let sample: Sample'(s32, 2)
//     var idx = 1
//     // @bug Expected sema_err_expr_not_const once generic method sema works.
//     sample.pickPair'(idx, 0)()
// }
