#global fileprivate

func pick(values: const [..] s32, idx: s32)->s32
{
    return values[idx]
}

#test
{
    const s: const [..] s32 = [1, 2, 3]
    #assert(s[0] == 1)
    #assert(s[2] == 3)
}

#test
{
    const a: [3] s32 = [4, 5, 6]
    const v = #run pick(a, 2)
    #assert(v == 6)
}

#test
{
    const v = #run pick([10, 20, 30], 1)
    #assert(v == 20)
}

#test
{
    const a: [3] s32 = [1, 2, 3]
    const s: const [..] s32 = a
    #assert(@countof(s) == 3)
    #assert(s[1] == 2)
}

func pickRef(values: const &[..] s32, idx: s32)->s32
{
    return values[idx]
}

func sliceRefWindow()->u64
{
    var arr: [5] s32 = [10, 20, 30, 40, 50]
    let arrRef: &[5] s32 = &arr
    let mid = arrRef[1 to 3]
    return @countof(mid) + cast(u64) mid[0] + cast(u64) mid[2]
}

func textRefWindow()->string
{
    let text = "string"
    let textRef: const &string = &text
    return textRef[1 to 3]
}

#test
{
    func runPickRef()->s32
    {
        var arr: [3] s32 = [4, 5, 6]
        let values: [..] s32 = arr
        let valuesRef: const &[..] s32 = &values
        return pickRef(valuesRef, 2)
    }

    const V0 = #run runPickRef()
    const V1 = #run sliceRefWindow()
    const V2 = #run textRefWindow()
    #assert(V0 == 6)
    #assert(V1 == 63'u64)
    #assert(V2 == "tri")
}
