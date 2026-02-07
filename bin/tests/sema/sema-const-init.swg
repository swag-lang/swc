#global internal

const A: s32 = 10
const B: s32 = 10's8

const C: bool = 10's8                // swc-expected-error {{sema_err_cannot_cast}}
const C1: bool = cast(bool) 10's8
#assert(C1 == true)

const D: u8 = -1's8                  // swc-expected-error {{sema_err_signed_unsigned}}
const D1: u8 = cast(u8) -1's8        // swc-expected-error {{sema_err_signed_unsigned}}

const E: s8 = 255'u8                 // swc-expected-error {{sema_err_signed_unsigned}}
const E1: s8 = cast(s8) 255'u8       // swc-expected-error {{sema_err_signed_unsigned}}

const F: u8 = 256'u16                // swc-expected-error {{sema_err_literal_overflow}}
const F1: u8 = cast(u8) 256'u16      // swc-expected-error {{sema_err_literal_overflow}}

const G: s32 = 1.9                   // swc-expected-error {{sema_err_cannot_cast}}
const G1: s32 = cast(s32) 1.9
#assert(G1 == 1)

const H: u8 = true                   // swc-expected-error {{sema_err_cannot_cast}}
const H1: u8 = cast(u8) true
#assert(H1 == 1'u8)

const I: bool = 2'u8                 // swc-expected-error {{sema_err_cannot_cast}}
const I1: bool = cast(bool) 2'u8
#assert(I1 == true)

const J: rune = 65'u32
const J1: rune = cast(rune) 65'u32
#assert(J1 == 'A')

const K: u32 = 'A'
const K1: u32 = cast(u32) 'A'
#assert(K1 == 65'u32)

const L: f32 = 1'u8
const L1: f32 = cast(f32) 1'u8
#assert(L1 == 1)

const M: f64 = 1.0'f32
const M1: f64 = cast(f64) 1.0'f32
#assert(M1 == 1.0'f64)

const N: s64 = 1's32
const N1: s64 = cast(s64) 1's32
#assert(N1 == 1's64)

const O: u64 = 1'u32
const O1: u64 = cast(u64) 1'u32
#assert(O1 == 1'u64)

const P: u16 = 255'u8
const P1: u16 = cast(u16) 255'u8
#assert(P == 255'u16)
#assert(P1 == 255'u16)

const Q: s16 = -1's8
const Q1: s16 = cast(s16) -1's8
#assert(Q == -1's16)
#assert(Q1 == -1's16)

const R: u32 = 0xFF
const R1: u32 = cast(u32) 0xFF
#assert(R == 255'u32)
#assert(R1 == 255'u32)

const S: u64 = 0xFFFFFFFFF
const S1: u64 = cast(u64) 0xFFFFFFFFF
#assert(S == 0xFFFFFFFFF'u64)
#assert(S1 == 0xFFFFFFFFF'u64)

const T: f32 = 1.0
const T1: f32 = cast(f32) 1.0
#assert(T == 1.0'f32)
#assert(T1 == 1.0'f32)

const U: f64 = 1.0'f64
const U1: f64 = cast(f64) 1.0'f64
#assert(U == 1.0'f64)
#assert(U1 == 1.0'f64)
