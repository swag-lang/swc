#global fileprivate // swc-option suite-test

#test
{
    if true
    {
    }

    if false
    {
    }
    else
    {
    }

    if false
    {
    }
    elif true
    {
    }
    else
    {
    }
}

#test
{
    if true
    {
        var x = 0
    }

}

#test
{
    if true
    {
        var x = 0
    }
    else
    {
        var x = 1
    }
}

#test
{
    if true
    {
        if true
        {
            var x = 0
        }
    }
}

