#global fileprivate // swc-option suite-jit

#test
{
    func divEqInt()->s32
    {
        var v: s32 = 84
        v /= 2
        return v
    }

    const V = #run divEqInt()
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    func divEqFloat()->f32
    {
        var v: f32 = 84.0'f32
        v /= 2.0'f32
        return v
    }

    const V = #run divEqFloat()
    #assert(#typeof(V) == f32)
    #assert(V == 42.0'f32)
}
