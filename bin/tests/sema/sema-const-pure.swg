#global internal

#test
{
    func add(a: s32, b: s32) -> s32 => a + b
    const A: s32 = add(1, 2)
    #assert(A == 3)
}

#test
{
    func clamp(a: s32, b: s32) -> s32 => @min(a, @max(b, 0's32))
    const B: s32 = clamp(5's32, -3's32)
    #assert(B == 0's32)
}

#test
{
    func roots(a: f64) -> f64 => @sqrt(a) + @abs(-2.0'f64)
    const C: f64 = roots(9.0'f64)
    #assert(C == 5.0'f64)
}

#test
{
    func trig(a: f64) -> f64 => @sin(a) + @cos(a) + @tan(a)
    const D: f64 = trig(0.0'f64)
    #assert(D == 1.0'f64)
}

#test
{
    func hyper(a: f64) -> f64 => @sinh(a) + @cosh(a) + @tanh(a)
    const E: f64 = hyper(0.0'f64)
    #assert(E == 1.0'f64)
}

#test
{
    func angles(a: f64, b: f64) -> f64 => @asin(a) + @acos(b) + @atan(a)
    const F: f64 = angles(0.0'f64, 1.0'f64)
    #assert(F == 0.0'f64)
}

#test
{
    func logs(a: f64) -> f64 => @log(a) + @log2(8.0'f64) + @log10(a)
    const G: f64 = logs(1.0'f64)
    #assert(G == 3.0'f64)
}

#test
{
    func rounds(a: f64) -> f64 => @floor(a) + @ceil(a) + @trunc(-a) + @round(1.4'f64)
    const H: f64 = rounds(1.9'f64)
    #assert(H == 3.0'f64)
}

#test
{
    func exps(a: f64, b: f64) -> f64 => @exp(a) + @exp2(b)
    const I: f64 = exps(0.0'f64, 3.0'f64)
    #assert(I == 9.0'f64)
}

#test
{
    func combos(a: f64, b: f64) -> f64 => @pow(a, b) + @muladd(2.0'f64, 3.0'f64, 4.0'f64) + @atan2(0.0'f64, 1.0'f64)
    const J: f64 = combos(2.0'f64, 4.0'f64)
    #assert(J == 26.0'f64)
}

#test
{
    func add(a: s32, b: s32) -> s32 => a + b
    var v: s32 = 2
    const K: s32 = add(1, v) // swc-expected-error {{sema_err_expr_not_const}}
}

#test
{
    func bad(a: f64) -> f64 => @sqrt(a)
    const L: f64 = bad(-1.0'f64) // swc-expected-error {{sema_err_intrinsic_invalid_argument}}
}
