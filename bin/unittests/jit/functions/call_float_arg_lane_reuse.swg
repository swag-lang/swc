#global private

func sum4f(a, b, c, d: f32)->f32
{
    return a + b + c + d
}

func reuseFloatAcrossArgLanes(v: f32)->f32
{
    return sum4f(v, v, v, v)
}

#test
{
    const ok = #run
    {
        return reuseFloatAcrossArgLanes(1.5) == 6.0
    }
    #assert(ok)
}
