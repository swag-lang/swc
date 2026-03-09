#global fileprivate

func makeConstArrayString()->string
{
    const data: [3] u8 = [120, 121, 122]
    return cast(string) data
}

#test
{
    func localArrayToSliceView()->bool
    {
        var data: [4] s32 = [1, 2, 3, 4]
        let values = cast([..] s32) data
        return @countof(values) == 4 and values[0] == 1 and values[1] == 2 and values[3] == 4
    }

    const V = #run localArrayToSliceView()
    #assert(V)
}

#test
{
    const text = #run makeConstArrayString()

    #assert(@countof(text) == 3)
    #assert(text == "xyz")
}
