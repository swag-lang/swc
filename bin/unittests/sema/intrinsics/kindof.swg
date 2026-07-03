#global private

func semaTest001()
{
    var a: any
    var b = @kindof(a)
    #assert(#typeof(b) == typeinfo)
}

func semaTest002()
{
    var x: s32
    var a: any = @mkany(&x, s32)
    var b = @kindof(a)
    @assert(b == s32)
}

func semaTest003()
{
    var x: f32
    var a: any = @mkany(cast(*void) &x, f32)
    var b = @kindof(a)
    @assert(b == f32)
}
