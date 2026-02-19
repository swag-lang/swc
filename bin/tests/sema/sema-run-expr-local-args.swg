#global internal

struct AbiPair
{
    a: s32
    b: s32
}

struct AbiPayload
{
    a0: u64
    a1: u64
    a2: u64
    a3: u64
}

#test
{
    func passString(text: string)->string { return text }
    const V = #run passString("abi-string")
    #assert(V == "abi-string")
}

#test
{
    func passArray(values: [4] s32)->[4] s32 { return values }
    const V = #run passArray([11, 22, 33, 44])
    #assert(V[0] == 11)
    #assert(V[3] == 44)
}

#test
{
    func passPair(value: AbiPair)->AbiPair { return value }
    const V = #run passPair({a: 9, b: 13})
    #assert(V.a == 9)
    #assert(V.b == 13)
}

#test
{
    func passPair(value: AbiPair)->s32 { return value.a + value.b }
    const V = #run passPair({a: 9, b: 13})
    #assert(V == 22)
}

#test
{
    func passPayload(value: AbiPayload)->AbiPayload { return value }
    const V = #run passPayload({a0: 10'u64, a1: 20'u64, a2: 30'u64, a3: 40'u64})
    #assert(V.a0 == 10'u64)
    #assert(V.a3 == 40'u64)
}

#test
{
    func passPointer(value: *void)->*void { return value }
    const V = #run passPointer(null)
    #assert(V == null)
}

// #test
// {
//     func passMixed(a: s32, b: string, c: AbiPair, d: [2] s32, e: *void)->s32 { return a + c.a + d[1] }
//     const V = #run passMixed(3, "mix", {a: 10, b: 11}, [8, 9], null)
//     #assert(V == 22)
// }

// #test
// {
//     func passConstRef(value: const &AbiPair)->s32 { return value.b }
//     var p: AbiPair = {a: 6, b: 7}
//     const V = #run passConstRef(p)
//     #assert(V == 7)
// }
