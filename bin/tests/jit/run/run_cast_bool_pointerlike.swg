#global fileprivate

#test
{
    func stringToBool()->bool
    {
        let empty = cast(string) null
        let text: string = "x"
        return !cast(bool) empty and cast(bool) text
    }

    const V = #run stringToBool()
    #assert(V)
}

#test
{
    func sliceToBool()->bool
    {
        let empty = cast([..] s32) null
        var data: [2] s32 = [1, 2]
        let values = cast([..] s32) data
        return !cast(bool) empty and cast(bool) values
    }

    const V = #run sliceToBool()
    #assert(V)
}
