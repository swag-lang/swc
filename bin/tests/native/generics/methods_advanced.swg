#global fileprivate

// @bug Generic methods declared inside an impl of a generic struct are parsed,
// @bug but sema does not bind the method generic parameters yet.
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
//     let sample: Sample'(s32, 4) = {values: [10, 20, 30, 40]}
//     let pair = sample.pairWith'(string)("ten")
//
//     #assert(#typeof(pair.first) == s32)
//     #assert(#typeof(pair.second) == string)
//     @assert(pair.first == 10)
//     @assert(pair.second == "ten")
// }
//
// #test
// {
//     let sample: Sample'(u16, 3) = {values: [1'u16, 2, 3]}
//     let triple = sample.makeTriple'(u8, bool)(9'u8, true)
//
//     #assert(#typeof(triple.first) == u16)
//     #assert(#typeof(triple.second) == u8)
//     #assert(#typeof(triple.third) == bool)
//     @assert(triple.first == 1'u16)
//     @assert(triple.second == 9'u8)
//     @assert(triple.third == true)
// }
//
// #test
// {
//     let sample: Sample'(s32, 4) = {values: [11, 22, 33, 44]}
//     let picked = sample.pickPair'(1, 3)()
//
//     #assert(#typeof(picked.first) == s32)
//     #assert(#typeof(picked.second) == s32)
//     @assert(picked.first == 22)
//     @assert(picked.second == 44)
//     @assert(picked.total == 4)
// }
//
// #test
// {
//     let sample: Sample'(s32, 4) = {values: [100, 200, 300, 400]}
//     let mixed = sample.makeIndexedTriple'(u16, string, 0, 2)(7'u16, "done")
//
//     #assert(#typeof(mixed.first) == s32)
//     #assert(#typeof(mixed.second) == u16)
//     #assert(#typeof(mixed.third) == string)
//     @assert(mixed.first == 100)
//     @assert(mixed.second == 7'u16)
//     @assert(mixed.third == "done")
//     @assert(mixed.total == 2)
// }
