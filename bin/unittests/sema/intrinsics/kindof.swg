#global private

func semaTest001()
{
    var a: #null any
    var b = Swag.kindOf(a)
    #assert(#typeof(b) == typeinfo)
}

func semaTest002()
{
    var x: s32
    var a: any = Swag.makeAny(&x, s32)
    var b      = Swag.kindOf(a)
    Swag.assert(b == s32)
}

func semaTest003()
{
    var x: f32
    var a: any = Swag.makeAny(cast(*void) &x, f32)
    var b      = Swag.kindOf(a)
    Swag.assert(b == f32)
}
