#global fileprivate // swc-option suite-test

var gFloatF32: f32
var gFloatF64: f64
func takes_f32(v: f32) { gFloatF32 = v }
func takes_f64(v: f64) { gFloatF64 = v }




#test
{
    var a: s32 = -10
    takes_f32(a)
    takes_f64(a)
    @assert(gFloatF32 == -10.0)
    @assert(gFloatF64 == -10.0)
}

#test
{
    var a: s64 = -10
    takes_f64(a)
    @assert(gFloatF64 == -10.0)
}


#test
{
    var a: u32 = 10
    takes_f32(a)
    takes_f64(a)
    @assert(gFloatF32 == 10.0)
    @assert(gFloatF64 == 10.0)
}



