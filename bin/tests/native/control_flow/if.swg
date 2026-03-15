#global fileprivate // swc-option suite-test

#test
{
    var state = 0
    if true
    {
        state += 1
    }

    if false
    {
        state += 10
    }
    else
    {
        state += 100
    }

    if false
    {
        state += 1000
    }
    elif true
    {
        state += 10000
    }
    else
    {
        state += 100000
    }
    @assert(state == 10101)
}

#test
{
    var count = 0
    if true
    {
        var x = 0
        count += 1
    }
    @assert(count == 1)
}

#test
{
    var value = 0
    if true
    {
        value = 0
    }
    else
    {
        value = 1
    }
    @assert(value == 0)
}

#test
{
    var count = 0
    if true
    {
        if true
        {
            var x = 0
            count += 1
        }
    }
    @assert(count == 1)
}

