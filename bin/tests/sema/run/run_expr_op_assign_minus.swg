#global internal

#test
{
    func minusEqInt()->s32
    {
        var v: s32 = 50
        v -= 8
        return v
    }

    const V = #run minusEqInt()
    #assert(#typeof(V) == s32)
    #assert(V == 42)
}

#test
{
    func minusEqFloat()->f32
    {
        var v: f32 = 44.5'f32
        v -= 2.5'f32
        return v
    }

    const V = #run minusEqFloat()
    #assert(#typeof(V) == f32)
    #assert(V == 42.0'f32)
}
