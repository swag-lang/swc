#global private

func toto()->{x: s32, y: bool}
{
    return {42, true}
}

#test
{
    let s = toto()
    #assert(#typeof(s).kind == .Struct)
    Swag.assert(s.x == 42)
    Swag.assert(s.y)
}

#test
{
    var st1: struct { x: s32; y: s32 }
    let a = st1.x == 1
    let b = st1.y == 2
    #assert(#sizeof(st1) == 8)
    Swag.assert(st1.x == 0)
    Swag.assert(st1.y == 0)
}

#test
{
    let s = toto()
    Swag.assert(s.x == 42)
    Swag.assert(s.y)
}

#test
{
    let s = toto()
    var t: struct { x: s32; y: bool }
    t.x = 1
    t.y = false
    Swag.assert(t.x == 1)
    Swag.assert(!t.y)
}
