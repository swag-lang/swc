#global fileprivate

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

func continueInScope()->s32
{
    var count: s32 = 0

    #scope(Loop)
    {
        count += 1
        if count == 4 do
            break
        continue
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
#assert(#run continueInScope() == 4)
#assert(#run breakToNearestNamedScope() == 2)
