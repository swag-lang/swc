#global internal

#test
{
    var a: any
    var b = @kindof(a)
    #assert(#typeof(b) == typeinfo)
}

#test
{
    var x: s32
    var a: any = @mkany(&x, s32)
    var b = @kindof(a)
    @assert(b == s32)
}

#test
{
    var x: f32
    var a: any = @mkany(cast(*void) &x, f32)
    var b = @kindof(a)
    @assert(b == f32)
}
