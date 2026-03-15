#global fileprivate // swc-option suite-test

#test
{
    var result = 0
    if var x = 1
    {
        var y = x
        result = y
    }
    else
    {
        var z = x
        result = z
    }
    @assert(result == 1)
}

#test
{
    var result = 0
    if var x: s32 = 1 where x
    {
        var y = x
        result = y
    }
    @assert(result == 1)
}

