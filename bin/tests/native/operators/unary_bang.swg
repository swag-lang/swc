#global fileprivate // swc-option suite-test

func unaryBangBool(a: bool)->bool
{
    return !a
}

func unaryBangInt(a: s32)->bool
{
    return !a
}

func unaryBangPointer(a: *void)->bool
{
    return !a
}

func unaryBangBang(a: s32)->bool
{
    return !(!a)
}

#test
{
    #assert(#typeof(unaryBangBool(true)) == bool)
    #assert(#typeof(unaryBangInt(0)) == bool)
    #assert(#typeof(unaryBangPointer(null)) == bool)

    @assert(!unaryBangBool(true))
    @assert(unaryBangBool(false))
    @assert(unaryBangInt(0))
    @assert(!unaryBangInt(1))
    @assert(unaryBangPointer(null))
    @assert(!unaryBangPointer(cast(*void) 0x1000'u64))
    @assert(!unaryBangBang(0))
    @assert(unaryBangBang(12))
}
