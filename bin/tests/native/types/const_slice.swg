#global fileprivate // swc-option suite-test

func pick(values: const [..] s32, idx: s32)->s32
{
    return values[idx]
}

#test
{
    const s: const [..] s32 = [1, 2, 3]
    #assert(s[0] == 1)
    #assert(s[2] == 3)

    const a: [3] s32 = [4, 5, 6]
    const view: const [..] s32 = a
    @assert(pick(a, 2) == 6)
    @assert(pick([10, 20, 30], 1) == 20)
    @assert(@countof(view) == 3)
    @assert(view[1] == 5)
}
