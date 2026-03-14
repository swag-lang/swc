#global fileprivate // swc-option suite-test

#test
{
    if var x = 1
    {
        var y = x
    }
    else
    {
        var z = x
    }

}

#test
{
    if var x: s32 = 1 where x
    {
        var y = x
    }
}

