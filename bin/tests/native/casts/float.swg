#global fileprivate // swc-option suite-test

func takes_f32(v: f32) {}
func takes_f64(v: f64) {}




#test
{
    var a: s32 = -10
    takes_f32(a)
    takes_f64(a)
}

#test
{
    var a: s64 = -10
    takes_f64(a)
}


#test
{
    var a: u32 = 10
    takes_f32(a)
    takes_f64(a)
}



