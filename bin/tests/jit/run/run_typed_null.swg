#global fileprivate

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
