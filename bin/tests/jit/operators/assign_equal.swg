#global fileprivate

enum AssignEqEnum: u16
{
    A = 1
    B = 2
}

#test
{
    func assignInt()->s32
    {
        var v: s32 = 1
        v = 42
        return v
    }

    const V = #run assignInt()
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    func assignFloat()->f64
    {
        var v: f64 = 1.5'f64
        v = 42.0'f64
        return v
    }

    const V = #run assignFloat()
    #assert(#typeof(V) == f64)
    #assert(V == 42.0'f64)
}

#test
{
    func assignBool()->bool
    {
        var v: bool = false
        v = true
        return v
    }

    const V = #run assignBool()
    #assert(#typeof(V) == bool)
    #assert(V)
}

#test
{
    func assignPointer()->bool
    {
        var p: *void = null
        p = cast(*void) 0x1234'u64
        return p != null
    }

    const V = #run assignPointer()
    #assert(V)
}

#test
{
    func assignEnum()->AssignEqEnum
    {
        var v: AssignEqEnum = AssignEqEnum.A
        v = AssignEqEnum.B
        return v
    }

    const V = #run assignEnum()
    #assert(#typeof(V) == AssignEqEnum)
    #assert(cast(u16) V == 2'u16)
}
