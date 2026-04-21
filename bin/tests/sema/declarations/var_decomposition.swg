#global fileprivate

func toto()->{x: s32, y: bool}
{
    return {42, true}
}

#test
{
    let s = toto()
    #assert(#typeof(s).kind == .Struct)
    let (a, b) = s
    #assert(#typeof(a) == s32)
    #assert(#typeof(b) == bool)
    let (c, ?) = s
    #assert(#typeof(c) == s32)
    let (?, d) = s
    #assert(#typeof(d) == bool)
}
