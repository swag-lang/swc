#global fileprivate // swc-option suite-jit

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
