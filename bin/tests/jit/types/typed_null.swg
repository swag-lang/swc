#global fileprivate // swc-option suite-jit

#test
{
    func typedNullString()->bool
    {
        let value = cast(string) null
        return value == null and @countof(value) == 0
    }

    const V = #run typedNullString()
    #assert(V)
}

#test
{
    func typedNullSlice()->bool
    {
        let value = cast([..] s32) null
        return value == null and @countof(value) == 0
    }

    const V = #run typedNullSlice()
    #assert(V)
}

#test
{
    func typedNullAny()->bool
    {
        let value = cast(any) null
        return value == null
    }

    const V = #run typedNullAny()
    #assert(V)
}

#test
{
    func typedNullConstBytes()->bool
    {
        let value = cast(const [..] u8) null
        return value == null and @countof(value) == 0
    }

    const V = #run typedNullConstBytes()
    #assert(V)
}

#test
{
    func typedNullPointerOrelse()->bool
    {
        let value = cast(*s32) null
        var fallback: s32 = 19
        let resolved = value orelse &fallback
        return value == null and resolved == &fallback and dref resolved == 19
    }

    const V = #run typedNullPointerOrelse()
    #assert(V)
}

#test
{
    func typedNullConditional(flag: bool)->bool
    {
        let left = cast(string) null
        let right: string = "ok"
        let resolved = flag ? left : right
        if flag do
            return resolved == null
        return resolved == "ok"
    }

    const V0 = #run typedNullConditional(true)
    const V1 = #run typedNullConditional(false)
    #assert(V0)
    #assert(V1)
}
