#global if #command == Swag.CompilerCommand.Test
#global private

func pushContextRestoresAfterContinue()->bool
{
    let base   = Swag.getContext()
    var pushed = base[]
    pushed.user0 = 0xC071E

    var reachedTail = 0
    for index in 4
    {
        if Swag.getContext() != base or Swag.getContext().user0 != base.user0 do
            return false

        System.pushContext(pushed)
        {
            if Swag.getContext() != &pushed or Swag.getContext().user0 != pushed.user0 do
                return false

            if index != 3 do
                continue
        }

        reachedTail += 1
        if Swag.getContext() != base or Swag.getContext().user0 != base.user0 do
            return false
    }

    return reachedTail == 1 and Swag.getContext() == base and Swag.getContext().user0 == base.user0
}

func pushContextRestoresAfterBreak()->bool
{
    let base   = Swag.getContext()
    var pushed = base[]
    pushed.user0 = 0xBEEA

    var iterations = 0
    for 5
    {
        if Swag.getContext() != base or Swag.getContext().user0 != base.user0 do
            return false

        System.pushContext(pushed)
        {
            if Swag.getContext() != &pushed or Swag.getContext().user0 != pushed.user0 do
                return false
            iterations += 1
            break
        }

        return false
    }

    return iterations == 1 and Swag.getContext() == base and Swag.getContext().user0 == base.user0
}

func pushContextRestoresAfterReturn()->bool
{
    let base   = Swag.getContext()
    var pushed = base[]
    pushed.user0 = 0xCA11EE

    System.pushContext(pushed)
    {
        if Swag.getContext() != &pushed or Swag.getContext().user0 != pushed.user0 do
            return false
        return true
    }

    return false
}

#test
{
    Swag.assert(pushContextRestoresAfterContinue())
    Swag.assert(pushContextRestoresAfterBreak())

    let base      = Swag.getContext()
    let baseUser0 = base.user0
    Swag.assert(pushContextRestoresAfterReturn())
    Swag.assert(Swag.getContext() == base)
    Swag.assert(Swag.getContext().user0 == baseUser0)
}
