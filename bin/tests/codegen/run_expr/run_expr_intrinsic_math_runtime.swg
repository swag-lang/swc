#global fileprivate

#test
{
    #[Swag.NoInline]
    func minS32(a, b: s32)->s32 => @min(a, b)
    #[Swag.NoInline]
    func maxS32(a, b: s32)->s32 => @max(a, b)
    #[Swag.NoInline]
    func absS32(v: s32)->s32 => @abs(v)
    #[Swag.NoInline]
    func absF64(v: f64)->f64 => @abs(v)

    #[Swag.NoInline]
    func sqrtF64(v: f64)->f64 => @sqrt(v)
    #[Swag.NoInline]
    func sinF64(v: f64)->f64 => @sin(v)
    #[Swag.NoInline]
    func cosF64(v: f64)->f64 => @cos(v)
    #[Swag.NoInline]
    func tanF64(v: f64)->f64 => @tan(v)

    #[Swag.NoInline]
    func sinhF64(v: f64)->f64 => @sinh(v)
    #[Swag.NoInline]
    func coshF64(v: f64)->f64 => @cosh(v)
    #[Swag.NoInline]
    func tanhF64(v: f64)->f64 => @tanh(v)

    #[Swag.NoInline]
    func asinF64(v: f64)->f64 => @asin(v)
    #[Swag.NoInline]
    func acosF64(v: f64)->f64 => @acos(v)
    #[Swag.NoInline]
    func atanF64(v: f64)->f64 => @atan(v)
    #[Swag.NoInline]
    func atan2F64(a, b: f64)->f64 => @atan2(a, b)

    #[Swag.NoInline]
    func logF64(v: f64)->f64 => @log(v)
    #[Swag.NoInline]
    func log2F64(v: f64)->f64 => @log2(v)
    #[Swag.NoInline]
    func log10F64(v: f64)->f64 => @log10(v)

    #[Swag.NoInline]
    func floorF64(v: f64)->f64 => @floor(v)
    #[Swag.NoInline]
    func ceilF64(v: f64)->f64 => @ceil(v)
    #[Swag.NoInline]
    func truncF64(v: f64)->f64 => @trunc(v)
    #[Swag.NoInline]
    func roundF64(v: f64)->f64 => @round(v)

    #[Swag.NoInline]
    func expF64(v: f64)->f64 => @exp(v)
    #[Swag.NoInline]
    func exp2F64(v: f64)->f64 => @exp2(v)
    #[Swag.NoInline]
    func powF64(a, b: f64)->f64 => @pow(a, b)
    #[Swag.NoInline]
    func mulAddF64(a, b, c: f64)->f64 => @muladd(a, b, c)

    #assert(#run minS32(4, -2) == -2)
    #assert(#run maxS32(4, -2) == 4)
    #assert(#run absS32(-9) == 9)
    #assert(#run absF64(-7.5) == 7.5)

    #assert(#run sqrtF64(9.0) == 3.0)
    #assert(#run sinF64(0.0) == 0.0)
    #assert(#run cosF64(0.0) == 1.0)
    #assert(#run tanF64(0.0) == 0.0)

    #assert(#run sinhF64(0.0) == 0.0)
    #assert(#run coshF64(0.0) == 1.0)
    #assert(#run tanhF64(0.0) == 0.0)

    #assert(#run asinF64(0.0) == 0.0)
    #assert(#run acosF64(1.0) == 0.0)
    #assert(#run atanF64(0.0) == 0.0)
    #assert(#run atan2F64(0.0, 1.0) == 0.0)

    #assert(#run logF64(1.0) == 0.0)
    #assert(#run log2F64(1.0) == 0.0)
    #assert(#run log10F64(1.0) == 0.0)

    #assert(#run floorF64(-1.1) == -2.0)
    #assert(#run ceilF64(-1.75) == -1.0)
    #assert(#run truncF64(1.75) == 1.0)
    #assert(#run roundF64(-2.5) == -3.0)

    #assert(#run expF64(0.0) == 1.0)
    #assert(#run exp2F64(0.0) == 1.0)
    #assert(#run powF64(2.0, 10.0) == 1024.0)
    #assert(#run mulAddF64(2.0, 3.0, 4.0) == 10.0)
}
