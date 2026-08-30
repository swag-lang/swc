#global private     //

// ============================================================
// Compile-time constant folding — f32 inputs
// ============================================================

#test
{
    const A:  f64 = Swag.sqrt(4.0'f32)
    const B:  f64 = Swag.sin(0.0'f32)
    const C:  f64 = Swag.cos(0.0'f32)
    const D:  f64 = Swag.tan(0.0'f32)
    const E:  f64 = Swag.sinh(0.0'f32)
    const F:  f64 = Swag.cosh(0.0'f32)
    const G:  f64 = Swag.tanh(0.0'f32)
    const H:  f64 = Swag.asin(0.0'f32)
    const I:  f64 = Swag.acos(1.0'f32)
    const J:  f64 = Swag.atan(0.0'f32)
    const K:  f64 = Swag.log(1.0'f32)
    const L:  f64 = Swag.log2(1.0'f32)
    const M:  f64 = Swag.log10(1.0'f32)
    const N:  f64 = Swag.floor(1.9'f32)
    const O:  f64 = Swag.ceil(1.1'f32)
    const P:  f64 = Swag.trunc(-1.9'f32)
    const Q:  f64 = Swag.round(1.4'f32)
    const R:  f64 = Swag.abs(-3.0'f32)
    const S:  f64 = Swag.exp(0.0'f32)
    const T:  f64 = Swag.exp2(0.0'f32)
    const U:  f64 = Swag.atan2(0.0'f32, 1.0'f32)
    const V:  f64 = Swag.pow(2.0, 8.0'f32)
    const W:  f64 = Swag.muladd(2.0'f32, 3.0'f32, 4.0'f32)
    const X:  f64 = Swag.min(1.0, 2.0'f32)
    const Y:  f64 = Swag.max(1.0, 2.0'f32)
    const Z:  f64 = Swag.min(1.0'f64, 2.0'f64)
    const AA: f64 = Swag.max(1.0'f64, 2.0'f64)
    #assert(A == 2.0)
    #assert(B == 0.0)
    #assert(C == 1.0)
    #assert(D == 0.0)
    #assert(E == 0.0)
    #assert(F == 1.0)
    #assert(G == 0.0)
    #assert(H == 0.0)
    #assert(I == 0.0)
    #assert(J == 0.0)
    #assert(K == 0.0)
    #assert(L == 0.0)
    #assert(M == 0.0)
    #assert(N == 1.0)
    #assert(O == 2.0)
    #assert(P == -1.0)
    #assert(Q == 1.0)
    #assert(R == 3.0)
    #assert(S == 1.0)
    #assert(T == 1.0)
    #assert(U == 0.0)
    #assert(V == 256.0)
    #assert(W == 10.0)
    #assert(X == 1.0)
    #assert(Y == 2.0)
    #assert(Z == 1.0)
    #assert(AA == 2.0)
    Swag.assert(A == 2.0)
    Swag.assert(AA == 2.0)
}

// ============================================================
// Compile-time — min/max for integer types
// ============================================================

#test
{
    const A: s8 = Swag.min(1's8, 2's8)
    const B: s8 = Swag.max(1's8, 2's8)
    #assert(A == 1)
    #assert(B == 2)
    const C: s16 = Swag.min(-3's16, 7's16)
    const D: s16 = Swag.max(-3's16, 7's16)
    #assert(C == -3)
    #assert(D == 7)
    const E: s32 = Swag.min(1's32, 2's32)
    const F: s32 = Swag.max(1's32, 2's32)
    #assert(E == 1)
    #assert(F == 2)
    Swag.assert(C == -3)
    Swag.assert(F == 2)
}

#test
{
    const A: s64 = Swag.min(-5's64, 3's64)
    const B: s64 = Swag.max(-5's64, 3's64)
    #assert(A == -5)
    #assert(B == 3)
    Swag.assert(B == 3)
}

#test
{
    const A: u32 = Swag.min(10'u32, 20'u32)
    const B: u32 = Swag.max(10'u32, 20'u32)
    #assert(A == 10'u32)
    #assert(B == 20'u32)
    Swag.assert(B == 20'u32)
}

#test
{
    const A: u8 = Swag.min(1'u8, 2'u8)
    const B: u8 = Swag.max(1'u8, 2'u8)
    #assert(A == 1'u8)
    #assert(B == 2'u8)
    const C: u16 = Swag.min(3'u16, 1'u16)
    const D: u16 = Swag.max(3'u16, 1'u16)
    #assert(C == 1'u16)
    #assert(D == 3'u16)
    Swag.assert(D == 3'u16)
}

#test
{
    const A: u64 = Swag.min(1'u64, 0xFFFFFFFFFFFFFFFF'u64)
    const B: u64 = Swag.max(1'u64, 0xFFFFFFFFFFFFFFFF'u64)
    #assert(A == 1'u64)
    #assert(B == 0xFFFFFFFFFFFFFFFF'u64)
    Swag.assert(B == 0xFFFFFFFFFFFFFFFF'u64)
}

// ============================================================
// Compile-time — atan2 zero/zero
// ============================================================

#test
{
    const E: f64 = Swag.atan2(0.0'f32, 0.0'f32)
    #assert(E == 0.0)
    Swag.assert(E == 0.0)
}

// ============================================================
// Compile-time — additional folding coverage
// ============================================================

#test
{
    const A: f64 = Swag.sqrt(9.0'f64)
    const B: f64 = Swag.sqrt(1.0'f64)
    const C: f64 = Swag.sqrt(0.0'f64)
    #assert(A == 3.0)
    #assert(B == 1.0)
    #assert(C == 0.0)
}

#test
{
    const B: f64 = Swag.exp2(3.0'f64)
    const C: f64 = Swag.exp2(10.0'f64)
    #assert(B == 8.0)
    #assert(C == 1024.0)
    Swag.assert(B == 8.0)
    Swag.assert(C == 1024.0)
}

#test
{
    const A: f64 = Swag.pow(3.0'f64, 2.0'f64)
    const B: f64 = Swag.pow(2.0'f64, 10.0'f64)
    const C: f64 = Swag.pow(10.0'f64, 0.0'f64)
    #assert(A == 9.0)
    #assert(B == 1024.0)
    #assert(C == 1.0)
    Swag.assert(A == 9.0)
}

#test
{
    const A: f64 = Swag.floor(-1.5'f64)
    const B: f64 = Swag.floor(2.9'f64)
    const C: f64 = Swag.ceil(-1.5'f64)
    const D: f64 = Swag.ceil(2.1'f64)
    const E: f64 = Swag.trunc(-2.9'f64)
    const F: f64 = Swag.trunc(2.9'f64)
    const I: f64 = Swag.round(2.4'f64)
    #assert(A == -2.0)
    #assert(B == 2.0)
    #assert(C == -1.0)
    #assert(D == 3.0)
    #assert(E == -2.0)
    #assert(F == 2.0)
    #assert(I == 2.0)
    Swag.assert(A == -2.0)
    Swag.assert(D == 3.0)
}

#test
{
    const A: f64 = Swag.log2(8.0'f64)
    const B: f64 = Swag.log2(1024.0'f64)
    const C: f64 = Swag.log10(100.0'f64)
    const D: f64 = Swag.log10(1000.0'f64)
    #assert(A == 3.0)
    #assert(B == 10.0)
    #assert(C == 2.0)
    #assert(D == 3.0)
    Swag.assert(A == 3.0)
    Swag.assert(C == 2.0)
}

#test
{
    const A: f64 = Swag.muladd(1.0'f64, 2.0'f64, 3.0'f64)
    const B: f64 = Swag.muladd(0.0'f64, 100.0'f64, 5.0'f64)
    const C: f64 = Swag.muladd(10.0'f64, 10.0'f64, -100.0'f64)
    #assert(A == 5.0)
    #assert(B == 5.0)
    #assert(C == 0.0)
    Swag.assert(A == 5.0)
    Swag.assert(C == 0.0)
}

// ============================================================
// Runtime wrappers for math intrinsics
// ============================================================

#[Swag.NoInline]
func rtSqrt64(v: f64)->f64 => Swag.sqrt(v)

#[Swag.NoInline]
func rtSin64(v: f64)->f64 => Swag.sin(v)

#[Swag.NoInline]
func rtCos64(v: f64)->f64 => Swag.cos(v)

#[Swag.NoInline]
func rtTan64(v: f64)->f64 => Swag.tan(v)

#[Swag.NoInline]
func rtSinh64(v: f64)->f64 => Swag.sinh(v)

#[Swag.NoInline]
func rtCosh64(v: f64)->f64 => Swag.cosh(v)

#[Swag.NoInline]
func rtTanh64(v: f64)->f64 => Swag.tanh(v)

#[Swag.NoInline]
func rtAsin64(v: f64)->f64 => Swag.asin(v)

#[Swag.NoInline]
func rtAcos64(v: f64)->f64 => Swag.acos(v)

#[Swag.NoInline]
func rtAtan64(v: f64)->f64 => Swag.atan(v)

#[Swag.NoInline]
func rtAtan2_64(y: f64, x: f64)->f64 => Swag.atan2(y, x)

#[Swag.NoInline]
func rtLog64(v: f64)->f64 => Swag.log(v)

#[Swag.NoInline]
func rtLog2_64(v: f64)->f64 => Swag.log2(v)

#[Swag.NoInline]
func rtLog10_64(v: f64)->f64 => Swag.log10(v)

#[Swag.NoInline]
func rtExp64(v: f64)->f64 => Swag.exp(v)

#[Swag.NoInline]
func rtExp2_64(v: f64)->f64 => Swag.exp2(v)

#[Swag.NoInline]
func rtPow64(a: f64, b: f64)->f64 => Swag.pow(a, b)

#[Swag.NoInline]
func rtFloor64(v: f64)->f64 => Swag.floor(v)

#[Swag.NoInline]
func rtCeil64(v: f64)->f64 => Swag.ceil(v)

#[Swag.NoInline]
func rtTrunc64(v: f64)->f64 => Swag.trunc(v)

#[Swag.NoInline]
func rtRound64(v: f64)->f64 => Swag.round(v)

#[Swag.NoInline]
func rtMuladd64(a: f64, b: f64, c: f64)->f64 => Swag.muladd(a, b, c)

#[Swag.NoInline]
func rtSqrt32(v: f32)->f32 => Swag.sqrt(v)

#[Swag.NoInline]
func rtSin32(v: f32)->f32 => Swag.sin(v)

#[Swag.NoInline]
func rtCos32(v: f32)->f32 => Swag.cos(v)

#[Swag.NoInline]
func rtFloor32(v: f32)->f32 => Swag.floor(v)

#[Swag.NoInline]
func rtCeil32(v: f32)->f32 => Swag.ceil(v)

#[Swag.NoInline]
func rtTrunc32(v: f32)->f32 => Swag.trunc(v)

#[Swag.NoInline]
func rtRound32(v: f32)->f32 => Swag.round(v)

// Runtime — sqrt
#test
{
    Swag.assert(rtSqrt64(0.0) == 0.0)
    Swag.assert(rtSqrt64(1.0) == 1.0)
    Swag.assert(rtSqrt64(4.0) == 2.0)
    Swag.assert(rtSqrt64(9.0) == 3.0)
    Swag.assert(rtSqrt64(16.0) == 4.0)
    Swag.assert(rtSqrt32(4.0'f32) == 2.0'f32)
    Swag.assert(rtSqrt32(25.0'f32) == 5.0'f32)
}

// Runtime — trig at zero
#test
{
    Swag.assert(rtSin64(0.0) == 0.0)
    Swag.assert(rtCos64(0.0) == 1.0)
    Swag.assert(rtTan64(0.0) == 0.0)

    let s = rtSin32(0.0'f32)
    let c = rtCos32(0.0'f32)
    Swag.assert(s == 0.0'f32)
    Swag.assert(c == 1.0'f32)
}

// Runtime — hyperbolic at zero
#test
{
    Swag.assert(rtSinh64(0.0) == 0.0)
    Swag.assert(rtCosh64(0.0) == 1.0)
    Swag.assert(rtTanh64(0.0) == 0.0)
}

// Runtime — inverse trig
#test
{
    Swag.assert(rtAsin64(0.0) == 0.0)
    Swag.assert(rtAcos64(1.0) == 0.0)
    Swag.assert(rtAtan64(0.0) == 0.0)
    Swag.assert(rtAtan2_64(0.0, 1.0) == 0.0)
    Swag.assert(rtAtan2_64(0.0, 0.0) == 0.0)
}

// Runtime — log / exp
#test
{
    Swag.assert(rtLog64(1.0) == 0.0)
    Swag.assert(rtLog2_64(1.0) == 0.0)
    Swag.assert(rtLog2_64(8.0) == 3.0)
    Swag.assert(rtLog2_64(1024.0) == 10.0)
    Swag.assert(rtLog10_64(1.0) == 0.0)
    Swag.assert(rtLog10_64(100.0) == 2.0)
    Swag.assert(rtLog10_64(1000.0) == 3.0)
}

#test
{
    Swag.assert(rtExp64(0.0) == 1.0)
    Swag.assert(rtExp2_64(0.0) == 1.0)
    Swag.assert(rtExp2_64(3.0) == 8.0)
    Swag.assert(rtExp2_64(10.0) == 1024.0)
}

// Runtime — pow
#test
{
    Swag.assert(rtPow64(2.0, 0.0) == 1.0)
    Swag.assert(rtPow64(2.0, 1.0) == 2.0)
    Swag.assert(rtPow64(2.0, 8.0) == 256.0)
    Swag.assert(rtPow64(2.0, 10.0) == 1024.0)
    Swag.assert(rtPow64(3.0, 2.0) == 9.0)
    Swag.assert(rtPow64(10.0, 0.0) == 1.0)
}

// Runtime — rounding
#test
{
    Swag.assert(rtFloor64(1.9) == 1.0)
    Swag.assert(rtFloor64(-1.5) == -2.0)
    Swag.assert(rtFloor64(2.0) == 2.0)
    Swag.assert(rtCeil64(1.1) == 2.0)
    Swag.assert(rtCeil64(-1.5) == -1.0)
    Swag.assert(rtCeil64(2.0) == 2.0)
    Swag.assert(rtTrunc64(-1.9) == -1.0)
    Swag.assert(rtTrunc64(2.9) == 2.0)
    Swag.assert(rtRound64(1.4) == 1.0)
    Swag.assert(rtRound64(2.5) == 3.0)
}

#test
{
    Swag.assert(rtFloor32(1.9'f32) == 1.0'f32)
    Swag.assert(rtFloor32(-1.5'f32) == -2.0'f32)
    Swag.assert(rtCeil32(1.1'f32) == 2.0'f32)
    Swag.assert(rtCeil32(-1.5'f32) == -1.0'f32)
    Swag.assert(rtTrunc32(-1.9'f32) == -1.0'f32)
    Swag.assert(rtTrunc32(2.9'f32) == 2.0'f32)
    Swag.assert(rtRound32(1.4'f32) == 1.0'f32)
    Swag.assert(rtRound32(2.5'f32) == 3.0'f32)
}

// Runtime — muladd
#test
{
    Swag.assert(rtMuladd64(2.0, 3.0, 4.0) == 10.0)
    Swag.assert(rtMuladd64(0.0, 100.0, 5.0) == 5.0)
    Swag.assert(rtMuladd64(10.0, 10.0, -100.0) == 0.0)
    Swag.assert(rtMuladd64(1.0, 1.0, 0.0) == 1.0)
}
