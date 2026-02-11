#global internal

#test
{
    const A: f64 = @sqrt(4.0'f32)
    const B: f64 = @sin(0.0'f32)
    const C: f64 = @cos(0.0'f32)
    const D: f64 = @tan(0.0'f32)
    const E: f64 = @sinh(0.0'f32)
    const F: f64 = @cosh(0.0'f32)
    const G: f64 = @tanh(0.0'f32)
    const H: f64 = @asin(0.0'f32)
    const I: f64 = @acos(1.0'f32)
    const J: f64 = @atan(0.0'f32)
    const K: f64 = @log(1.0'f32)
    const L: f64 = @log2(1.0'f32)
    const M: f64 = @log10(1.0'f32)
    const N: f64 = @floor(1.9'f32)
    const O: f64 = @ceil(1.1'f32)
    const P: f64 = @trunc(-1.9'f32)
    const Q: f64 = @round(1.4'f32)
    const R: f64 = @abs(-3.0'f32)
    const S: f64 = @exp(0.0'f32)
    const T: f64 = @exp2(0.0'f32)
    const U: f64 = @atan2(0.0'f32, 1.0'f32)
    const V: f64 = @pow(2.0, 8.0'f32)
    const W: f64 = @muladd(2.0'f32, 3.0'f32, 4.0'f32)
    const X: f64 = @min(1.0, 2.0'f32)
    const Y: f64 = @max(1.0, 2.0'f32)
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
}

#test
{
    var x: f64 = 4.0
    const A: f64 = @sqrt(x) // swc-expected-error {{sema_err_expr_not_const}}
}

#test
{
    const A: f64 = @sqrt(-1.0'f32) // swc-expected-error {{sema_err_intrinsic_invalid_argument}}
}

#test
{
    const B: f64 = @log(0.0'f32)   // swc-expected-error {{sema_err_intrinsic_invalid_argument}}
}

#test
{
    const C: f64 = @asin(2.0'f32)  // swc-expected-error {{sema_err_intrinsic_invalid_argument}}
}

#test
{
    const A: f64 = @acos(-2.0'f32) // swc-expected-error {{sema_err_intrinsic_invalid_argument}}
}

#test
{
    const B: f64 = @log2(-1.0'f32) // swc-expected-error {{sema_err_intrinsic_invalid_argument}}
}

#test
{
    const C: f64 = @log10(0.0'f32) // swc-expected-error {{sema_err_intrinsic_invalid_argument}}
}

#test
{
    const D: f64 = @pow(-1.0'f32, 0.5'f32) // swc-expected-error {{sema_err_intrinsic_invalid_argument}}
}

#test
{
    const E: f64 = @atan2(0.0'f32, 0.0'f32)
    #assert(E == 0.0)
}
