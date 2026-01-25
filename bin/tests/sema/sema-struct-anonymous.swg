#global internal

func toto()->{x: s32, y: bool}
{
    return {42, true}
}

#test
{
    let s = toto()
    #assert(#typeof(s).kind == .Struct)
}

#test
{
    var st1: struct { x: s32; y: s32 }
    st1.x = 1
    st1.y = 2
    @assert(st1.x == 1)
    @assert(st1.y == 2)
    #assert(#sizeof(st1) == 8)
}