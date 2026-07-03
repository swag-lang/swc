#global private

#test
{
    func contextFlagsAreCompiler()->bool
    {
        return @getcontext().runtimeFlags == .FromCompiler
    }

    const V = #run contextFlagsAreCompiler()
    #assert(V)
}

#test
{
    func canSwapContextPointer()->bool
    {
        let prev = @getcontext()
        var cxt = dref prev
        cxt.user0 = 0xA17E

        @setcontext(cxt)
        let swapped = @getcontext() == &cxt and @getcontext().user0 == 0xA17E
        @setcontext(prev)

        return swapped and @getcontext() == prev
    }

    const V = #run canSwapContextPointer()
    #assert(V)
}

#test
{
    func pinfosAreZeroed()->bool
    {
        return @countof(@pinfos.modules) == 0 and @countof(@pinfos.args) == 0
    }

    const V = #run pinfosAreZeroed()
    #assert(V)
}
