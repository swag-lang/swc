#global private

#test
{
    func contextFlagsAreCompiler()->bool
    {
        return Swag.getContext().runtimeFlags == .FromCompiler
    }

    const V = #run contextFlagsAreCompiler()
    #assert(V)
}

#test
{
    func canSwapContextPointer()->bool
    {
        let prev = Swag.getContext()
        var cxt  = prev[]
        cxt.user0 = 0xA17E

        Swag.setContext(cxt)
        let swapped = Swag.getContext() == &cxt and Swag.getContext().user0 == 0xA17E
        Swag.setContext(prev)

        return swapped and Swag.getContext() == prev
    }

    const V = #run canSwapContextPointer()
    #assert(V)
}

#test
{
    func pinfosAreZeroed()->bool
    {
        return (Swag.processInfos().modules).count == 0 and (Swag.processInfos().args).count == 0
    }

    const V = #run pinfosAreZeroed()
    #assert(V)
}
