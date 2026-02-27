#global fileprivate

const Cfg = #run dref @compiler.getBuildCfg()

#test
{
    func passAssert()->s32
    {
        @assert(true)
        return 42
    }

    const V = #run passAssert()
    #assert(V == 42)
}

#if Cfg.backend.emitAssert {
    #test
    {
        #assert(Cfg.backend.emitAssert == true)
    }
} #else {
    #test
    {
        func failAssert()->s32
        {
            @assert(false)
            return 7
        }

        const V = #run failAssert()
        #assert(V == 7)
    }
}
