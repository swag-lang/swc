#global private

func breakToNamedScope()->s32
{
    var count: s32 = 0

    #scope(Outer)
    {
        for 10
        {
            count += 1
            break to Outer
        }

        count = -10
    }

    return count
}

func breakToLabeledStatement()->s32
{
    var count: s32 = 0

    #scope(Up)
        for 10
    {
        count += 1
        break to Up
    }

    return count
}

// A '#scope' is transparent to the bare statements: both reach the enclosing loop.
func bareStatementsReachTheLoop()->s32
{
    var count: s32 = 0

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

    return count
}

func breakToNearestNamedScope()->s32
{
    var count: s32 = 0

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

    return count
}

#assert(#run breakToNamedScope() == 1)
#assert(#run breakToLabeledStatement() == 1)
#assert(#run bareStatementsReachTheLoop() == 4)
#assert(#run breakToNearestNamedScope() == 2)
