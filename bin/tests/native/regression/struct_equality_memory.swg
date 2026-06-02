#global fileprivate

// Regression: equality of aggregate (struct/array) operands wider than a machine
// register must compare the FULL value, not just the first machine word.
//
// The codegen scalar compare path loaded a single register-sized chunk from the
// operand address, so two memory-backed structs that differed only past the first
// field (e.g. same X, different Y) compared as equal. This silently corrupted, for
// instance, the Clipper polygon code (IntPoint{x,y} dedup), deforming rendered glyphs.
//
// Compile-time constant operands are folded correctly, so every case forces RUNTIME,
// memory-backed operands: values are stored into mutable globals and compared through
// `Swag.Optimize(false)` helpers so neither Sema nor the optimizer can fold them away.

struct P2 { x, y: s64 }            // 16 bytes -> B64 + B64
struct P3 { a, b, c: s32 }         // 12 bytes -> B64 + B32
struct PB { data: [9] u8 }         //  9 bytes -> B64 + B8
struct Big { p: P2, k: s64 }       // 24 bytes, nested struct

#[Swag.Optimize(false)]
func eqP2(a, b: P2)->bool => a == b
#[Swag.Optimize(false)]
func neP2(a, b: P2)->bool => a != b
#[Swag.Optimize(false)]
func eqP3(a, b: P3)->bool => a == b
#[Swag.Optimize(false)]
func eqPB(a, b: PB)->bool => a == b
#[Swag.Optimize(false)]
func eqBig(a, b: Big)->bool => a == b
#[Swag.Optimize(false)]
func eqArr3(a, b: [3] s64)->bool => a == b

var g_p2:  [4] P2
var g_p3:  [3] P3
var g_pb:  [3] PB
var g_big: [4] Big
var g_arr: [3] [3] s64

// 16-byte struct differing only in the SECOND field must not compare equal.
#test
{
    g_p2[0] = P2{0, 0}
    g_p2[1] = P2{0, 10000}        // same x, different y
    g_p2[2] = P2{0, 10000}        // identical to [1]
    g_p2[3] = P2{10000, 0}        // different x, same y

    @assert(neP2(g_p2[0], g_p2[1]))
    @assert(!eqP2(g_p2[0], g_p2[1]))
    @assert(eqP2(g_p2[1], g_p2[2]))
    @assert(neP2(g_p2[0], g_p2[3]))
    @assert(eqP2(g_p2[1], g_p2[1]))
}

// 12-byte struct differing only in the THIRD field (exercises B64 + B32 chunk).
#test
{
    g_p3[0] = P3{1, 2, 3}
    g_p3[1] = P3{1, 2, 9}         // differ in c only
    g_p3[2] = P3{1, 2, 3}         // identical to [0]

    @assert(!eqP3(g_p3[0], g_p3[1]))
    @assert(eqP3(g_p3[0], g_p3[2]))
}

// 9-byte struct differing only in the LAST byte (exercises B64 + B8 tail chunk).
#test
{
    g_pb[0] = PB{[1, 2, 3, 4, 5, 6, 7, 8, 0]}
    g_pb[1] = PB{[1, 2, 3, 4, 5, 6, 7, 8, 9]}    // differ in last byte
    g_pb[2] = PB{[1, 2, 3, 4, 5, 6, 7, 8, 9]}    // identical to [1]

    @assert(!eqPB(g_pb[0], g_pb[1]))
    @assert(eqPB(g_pb[1], g_pb[2]))
}

// Nested struct (24 bytes) differing deep inside the nested member / tail.
#test
{
    g_big[0] = Big{P2{5, 7}, 100}
    g_big[1] = Big{P2{5, 8}, 100}    // differ only in p.y
    g_big[2] = Big{P2{5, 7}, 200}    // differ only in k
    g_big[3] = Big{P2{5, 7}, 100}    // identical to [0]

    @assert(!eqBig(g_big[0], g_big[1]))
    @assert(!eqBig(g_big[0], g_big[2]))
    @assert(eqBig(g_big[0], g_big[3]))
}

// Static array equality is routed through the same aggregate compare path.
#test
{
    g_arr[0] = [1, 2, 3]
    g_arr[1] = [1, 2, 4]             // differ in last element
    g_arr[2] = [1, 2, 3]

    @assert(!eqArr3(g_arr[0], g_arr[1]))
    @assert(eqArr3(g_arr[0], g_arr[2]))
}
