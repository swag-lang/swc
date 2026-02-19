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
    const V1 = #run passString("abi-string-2")
    #assert(V1 == "abi-string-2")
    const V2 = #run passString("abi-string-3")
    #assert(V2 == "abi-string-3")
}

#test
{
    func passString(text: string, idx: s32)->u8 { return text[idx] }
    const V = #run passString("abi-string", 1)
    #assert(V == 98'u8)
    const V1 = #run passString("abi-string", 2)
    #assert(V1 == 'i''u8)
    const V2 = #run passString("abi-string", 9)
    #assert(V2 == 'g''u8)
}

#test
{
    func passArray(values: [4] s32)->[4] s32 { return values }
    const V = #run passArray([11, 22, 33, 44])
    #assert(V[0] == 11)
    #assert(V[3] == 44)
    const V1 = #run passArray([101, 202, 303, 404])
    #assert(V1[0] == 101)
    #assert(V1[3] == 404)
    const V2 = #run passArray([-1, -2, -3, -4])
    #assert(V2[0] == -1)
    #assert(V2[3] == -4)
}

#test
{
    func passPair(value: AbiPair)->AbiPair { return value }
    const V = #run passPair({a: 9, b: 13})
    #assert(V.a == 9)
    #assert(V.b == 13)
    const V1 = #run passPair({a: 91, b: 131})
    #assert(V1.a == 91)
    #assert(V1.b == 131)
    const V2 = #run passPair({a: -9, b: -13})
    #assert(V2.a == -9)
    #assert(V2.b == -13)
}

#test
{
    func passPair(value: AbiPair)->s32 { return value.a + value.b }
    const V = #run passPair({a: 9, b: 13})
    #assert(V == 22)
    const V1 = #run passPair({a: 90, b: 130})
    #assert(V1 == 220)
    const V2 = #run passPair({a: -90, b: 130})
    #assert(V2 == 40)
}

#test
{
    func passPayload(value: AbiPayload)->AbiPayload { return value }
    const V = #run passPayload({a0: 10'u64, a1: 20'u64, a2: 30'u64, a3: 40'u64})
    #assert(V.a0 == 10'u64)
    #assert(V.a3 == 40'u64)
    const V1 = #run passPayload({a0: 100'u64, a1: 200'u64, a2: 300'u64, a3: 400'u64})
    #assert(V1.a0 == 100'u64)
    #assert(V1.a3 == 400'u64)
    const V2 = #run passPayload({a0: 1'u64, a1: 2'u64, a2: 3'u64, a3: 4'u64})
    #assert(V2.a0 == 1'u64)
    #assert(V2.a3 == 4'u64)
}

#test
{
    func passPointer(value: *void)->*void { return value }
    const V = #run passPointer(null)
    #assert(V == null)
    const V1 = #run passPointer(cast(*void) 0x1234'u64)
    #assert(V1 == cast(*void) 0x1234'u64)
    const V2 = #run passPointer(cast(*void) 0xABCD'u64)
    #assert(V2 == cast(*void) 0xABCD'u64)
}

#test
{
    func passMixed(a: s32, b: string, c: AbiPair, d: [2] s32, e: *void)->s32 { return a + c.a + d[1] }
    const V = #run passMixed(3, "mix", {a: 10, b: 11}, [8, 9], null)
    #assert(V == 22)
    const V1 = #run passMixed(30, "mix2", {a: 100, b: 110}, [80, 90], cast(*void) 0x4567'u64)
    #assert(V1 == 220)
    const V2 = #run passMixed(-30, "mix3", {a: 100, b: 110}, [80, 90], cast(*void) 0xFEDC'u64)
    #assert(V2 == 160)
}

#test
{
    func passConstRef(value: const &AbiPair)->s32 { return value.b }
    const p: AbiPair = {a: 6, b: 7}
    const V = #run passConstRef(p)
    #assert(V == 7)
}
