#global #if #command == Swag.CompilerCommand.Test
#global private

func pushContextRestoresAfterContinue()->bool
{
    let base = @getcontext()
    var pushed = dref base
    pushed.user0 = 0xC071E

    var reachedTail = 0
    for 4
    {
        if @getcontext() != base or @getcontext().user0 != base.user0 do
            return false

        System.pushContext(pushed)
        {
            if @getcontext() != &pushed or @getcontext().user0 != pushed.user0 do
                return false

            if @index != 3 do
                continue
        }

        reachedTail += 1
        if @getcontext() != base or @getcontext().user0 != base.user0 do
            return false
    }

    return reachedTail == 1 and @getcontext() == base and @getcontext().user0 == base.user0
}

func pushContextRestoresAfterBreak()->bool
{
    let base = @getcontext()
    var pushed = dref base
    pushed.user0 = 0xBEEA

    var iterations = 0
    for 5
    {
        if @getcontext() != base or @getcontext().user0 != base.user0 do
            return false

        System.pushContext(pushed)
        {
            if @getcontext() != &pushed or @getcontext().user0 != pushed.user0 do
                return false
            iterations += 1
            break
        }

        return false
    }

    return iterations == 1 and @getcontext() == base and @getcontext().user0 == base.user0
}

func pushContextRestoresAfterReturn()->bool
{
    let base = @getcontext()
    var pushed = dref base
    pushed.user0 = 0xCA11EE

    System.pushContext(pushed)
    {
        if @getcontext() != &pushed or @getcontext().user0 != pushed.user0 do
            return false
        return true
    }

    return false
}

#test
{
    @assert(pushContextRestoresAfterContinue())
    @assert(pushContextRestoresAfterBreak())

    let base = @getcontext()
    let baseUser0 = base.user0
    @assert(pushContextRestoresAfterReturn())
    @assert(@getcontext() == base)
    @assert(@getcontext().user0 == baseUser0)
}
