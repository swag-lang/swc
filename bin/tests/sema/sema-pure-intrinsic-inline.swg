#global internal

func fsqrt(a: f64)->f64 => @sqrt(cast(f64) a)
func fsin(a: f64)->f64 => @sin(cast(f64) a)
func fcos(a: f64)->f64 => @cos(cast(f64) a)
func ftan(a: f64)->f64 => @tan(cast(f64) a)
func fsinh(a: f64)->f64 => @sinh(cast(f64) a)
func fcosh(a: f64)->f64 => @cosh(cast(f64) a)
func ftanh(a: f64)->f64 => @tanh(cast(f64) a)
func fasin(a: f64)->f64 => @asin(cast(f64) a)
func facos(a: f64)->f64 => @acos(cast(f64) a)
func fatan(a: f64)->f64 => @atan(cast(f64) a)
func fatan2(a: f64, b: f64)->f64 => @atan2(cast(f64) a, cast(f64) b)
func flog(a: f64)->f64 => @log(cast(f64) a)
func flog2(a: f64)->f64 => @log2(cast(f64) a)
func flog10(a: f64)->f64 => @log10(cast(f64) a)
func ffloor(a: f64)->f64 => @floor(cast(f64) a)
func fceil(a: f64)->f64 => @ceil(cast(f64) a)
func ftrunc(a: f64)->f64 => @trunc(cast(f64) a)
func fround(a: f64)->f64 => @round(cast(f64) a)
func fabs(a: f64)->f64 => @abs(cast(f64) a)
func fexp(a: f64)->f64 => @exp(cast(f64) a)
func fexp2(a: f64)->f64 => @exp2(cast(f64) a)
func fpow(a: f64, b: f64)->f64 => @pow(cast(f64) a, cast(f64) b)
func fmuladd(a: f64, b: f64, c: f64)->f64 => @muladd(cast(f64) a, cast(f64) b, cast(f64) c)

#test
{
    #assert(fsqrt(4.0) == 2.0)
    #assert(fsin(0.0) == 0.0)
    #assert(fcos(0.0) == 1.0)
    #assert(ftan(0.0) == 0.0)
    #assert(fsinh(0.0) == 0.0)
    #assert(fcosh(0.0) == 1.0)
    #assert(ftanh(0.0) == 0.0)
    #assert(fasin(0.0) == 0.0)
    #assert(facos(1.0) == 0.0)
    #assert(fatan(0.0) == 0.0)
    #assert(fatan2(0.0, 1.0) == 0.0)
    #assert(flog(1.0) == 0.0)
    #assert(flog2(1.0) == 0.0)
    #assert(flog10(1.0) == 0.0)
    #assert(ffloor(1.9) == 1.0)
    #assert(fceil(1.1) == 2.0)
    #assert(ftrunc(-1.9) == -1.0)
    #assert(fround(1.4) == 1.0)
    #assert(fabs(-3.0) == 3.0)
    #assert(fexp(0.0) == 1.0)
    #assert(fexp2(0.0) == 1.0)
    #assert(fpow(2.0, 8.0) == 256.0)
    #assert(fmuladd(2.0, 3.0, 4.0) == 10.0)
}

#test
{
    var x: f64 = 3.0
    #assert(fsqrt(x) == 2.0) // swc-expected-error {{sema_err_expr_not_const}}
}

const A = 42
func pure_intrinsic(a: s32)->s32 => #location(A).lineStart
#assert(pure_intrinsic(0) == 60)