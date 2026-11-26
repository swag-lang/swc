#global private

const A: s32 = 10
const B: s32 = 10_s8

const C1: bool = cast(bool, 10_s8)
#assert(C1 == true)

const G1: s32 = cast(s32, 1.9)
#assert(G1 == 1)

const H1: u8 = cast(u8, true)
#assert(H1 == 1_u8)

const I1: bool = cast(bool, 2_u8)
#assert(I1 == true)

const J:  rune = 65_u32
const J1: rune = cast(rune, 65_u32)
#assert(J1 == 'A')

const K:  u32 = 'A'
const K1: u32 = cast(u32, 'A')
#assert(K1 == 65_u32)

const L:  f32 = 1_u8
const L1: f32 = cast(f32, 1_u8)
#assert(L1 == 1)

const M:  f64 = 1.0_f32
const M1: f64 = cast(f64, 1.0_f32)
#assert(M1 == 1.0_f64)

const N:  s64 = 1_s32
const N1: s64 = cast(s64, 1_s32)
#assert(N1 == 1_s64)

const O:  u64 = 1_u32
const O1: u64 = cast(u64, 1_u32)
#assert(O1 == 1_u64)

const P:  u16 = 255_u8
const P1: u16 = cast(u16, 255_u8)
#assert(P == 255_u16)
#assert(P1 == 255_u16)

const Q:  s16 = -1_s8
const Q1: s16 = cast(s16, -1_s8)
#assert(Q == -1_s16)
#assert(Q1 == -1_s16)

const R:  u32 = 0xFF
const R1: u32 = cast(u32, 0xFF)
#assert(R == 255_u32)
#assert(R1 == 255_u32)

const S:  u64 = 0xFFFFFFFFF
const S1: u64 = cast(u64, 0xFFFFFFFFF)
#assert(S == 0xFFFFFFFFF_u64)
#assert(S1 == 0xFFFFFFFFF_u64)

const T:  f32 = 1.0
const T1: f32 = cast(f32, 1.0)
#assert(T == 1.0_f32)
#assert(T1 == 1.0_f32)

const U:  f64 = 1.0_f64
const U1: f64 = cast(f64, 1.0_f64)
#assert(U == 1.0_f64)
#assert(U1 == 1.0_f64)

const V = 1_s8
#assert(#typeof(V) == s8)

const W = -128_s8
#assert(#typeof(W) == s8)
#assert(W == -128_s8)

const X = 1_u8
#assert(#typeof(X) == u8)
