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

/*
#[Swag.PrintMicro]
#[Swag.Optimize(false)]
#run
{
    let a = cast(u64) @getcontext().runtimeFlags
    if a & 1 do
        @print(true)
    else do
        @print(false)
}
*/