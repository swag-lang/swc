#global fileprivate // swc-option sema-only
#global skip
#test
{
    func toto(x: func(s32)->s32)->s32
    {
        return x(4) * 4
    }

    @assert(toto(func(x) => x * x) == 64)
}
