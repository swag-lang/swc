#global private

func toto()->{x: s32, y: bool}
{
    return {x: 42, y: true}
}

func semaTest001()
{
    let s = toto()
    #assert(#typeof(s).kind == .Struct)
    let {x: a, y: b} = s
    #assert(#typeof(a) == s32)
    #assert(#typeof(b) == bool)
    let {x: c, y: _} = s
    #assert(#typeof(c) == s32)
    let {x: _, y: d} = s
    #assert(#typeof(d) == bool)
}
