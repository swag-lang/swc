#global fileprivate // swc-option suite-test

func stringToBool()->bool
{
    let empty = cast(string) null
    let text: string = "x"
    return !cast(bool) empty and cast(bool) text
}

func sliceToBool()->bool
{
    let empty = cast([..] s32) null
    var data: [2] s32 = [1, 2]
    let values = cast([..] s32) data
    return !cast(bool) empty and cast(bool) values
}

#test
{
    @assert(stringToBool())
    @assert(sliceToBool())
}
