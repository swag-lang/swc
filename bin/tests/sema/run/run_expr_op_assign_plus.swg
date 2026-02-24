#global internal

#test
{
    func plusEqInt()->s32
    {
        var v: s32 = 40
        v += 2
        return v
    }

    const V = #run plusEqInt()
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    func plusEqFloat()->f64
    {
        var v: f64 = 39.5'f64
        v += 2.5'f64
        return v
    }

    const V = #run plusEqFloat()
    #assert(#typeof(V) == f64)
    #assert(V == 42.0'f64)
}
