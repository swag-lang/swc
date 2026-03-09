#global fileprivate

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
    func pinfosAreZeroed()->bool
    {
        return @countof(@pinfos.modules) == 0 and @countof(@pinfos.args) == 0
    }

    const V = #run pinfosAreZeroed()
    #assert(V)
}
