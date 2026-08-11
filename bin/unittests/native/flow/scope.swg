#global private

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

// A '#scope' is transparent to the bare statements: both reach the enclosing loop.
#test
{
    var count = 0

    for 10
    {
        #scope(Grouped)
        {
            count += 1
            if count < 4 do
                continue
            break
        }
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
