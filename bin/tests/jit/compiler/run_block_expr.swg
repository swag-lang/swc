#global fileprivate

const ScalarValue = #run
{
    let base = 20
    return (base + 1) * 2
}

const PowerOfTwo: [4] s32 = #run
{
    var arr: [4] s32
    for i in arr do
        arr[i] = 1 << cast(u32) i
    return arr
}

#assert(#typeof(ScalarValue) == s32)
#assert(ScalarValue == 42)
#assert(#typeof(PowerOfTwo) == [4] s32)
#assert(PowerOfTwo[0] == 1)
#assert(PowerOfTwo[1] == 2)
#assert(PowerOfTwo[2] == 4)
#assert(PowerOfTwo[3] == 8)
