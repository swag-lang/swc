#global fileprivate

func compute(v: s32)->s32
{
    var x: s32 = v * 2
    return x + 2
}

#run
{
    var r: s32 = compute(20)
    @assert(r == 42)
}
