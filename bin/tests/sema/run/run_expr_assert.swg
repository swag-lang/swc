#global internal

#test
{
    func assertArg(value: bool)->s32
    {
        @assert(value)
        return 10
    }

    const V = #run assertArg(true)
    #assert(V == 10)
}

#test
{
    func assertBranch(flag: bool)->s32
    {
        if flag
        {
            @assert(true)
            return 20
        }

        @assert(false)
        return 21
    }

    const V = #run assertBranch(true)
    #assert(V == 20)
}

#test
{
    func assertArg(value: bool)->s32
    {
        @assert(value)
        return 30
    }

    const V = #run assertArg(false) // swc-expected-error {{sema_err_runtime_assert}}
}
