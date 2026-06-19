#global fileprivate

#test
{
    var count = 0

    #scope(Outer)
    {
        for 10
        {
            count += 1
            break to Outer
        }

        count = -10
    }

    @assert(count == 1)
}

#test
{
    var count = 0

    #scope(Up)
    for 10
    {
        count += 1
        break to Up
    }

    @assert(count == 1)
}

#test
{
    var count = 0

    #scope(Loop)
    {
        count += 1
        if count == 4 do
            break
        continue
    }

    @assert(count == 4)
}

#test
{
    var count = 0

    #scope(A)
    {
        #scope(A)
        {
            count += 1
            break to A
        }

        count += 1
        break to A
    }

    @assert(count == 2)
}
