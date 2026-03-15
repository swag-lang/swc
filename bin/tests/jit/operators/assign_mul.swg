#global fileprivate

#test
{
    func mulEqInt()->s32
    {
        var v: s32 = 6
        v *= 7
        return v
    }

    const V = #run mulEqInt()
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    func mulEqFloat()->f64
    {
        var v: f64 = 6.0'f64
        v *= 7.0'f64
        return v
    }

    const V = #run mulEqFloat()
    #assert(#typeof(V) == f64)
    #assert(V == 42.0'f64)
}
