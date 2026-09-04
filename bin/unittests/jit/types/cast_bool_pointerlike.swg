#global private

// A pointer-like value answers a bool cast with its first pointer-sized word against null, so
// only a '?' text or slice asks a question there. An empty one is still present.

#test
{
    func stringToBool()->bool
    {
        let empty         = cast(string?) null
        let text: string? = "x"
        let none: string? = ""
        return !cast(bool) empty and cast(bool) text and cast(bool) none
    }

    const V = #run stringToBool()
    #assert(V)
}

#test
{
    func sliceToBool()->bool
    {
        let empty             = cast([..] s32?) null
        var data:   [2] s32   = [1, 2]
        let values: [..] s32? = data
        return !cast(bool) empty and cast(bool) values
    }

    const V = #run sliceToBool()
    #assert(V)
}
