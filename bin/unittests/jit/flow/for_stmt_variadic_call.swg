#global fileprivate

func touch(params: ...)->u32
{
    return 1
}

#test
{
    func loopIndexUsedInVariadicForDo()->s32
    {
        var count: s32 = 0
        for i in 1 to 5 do
            count += cast(s32) touch(i, " ")
        return count
    }

    const V = #run loopIndexUsedInVariadicForDo()
    #assert(V == 5)
}
