#global private

func unaryBangBool(a: bool)->bool
{
    return !a
}

func unaryBangInt(a: s32)->bool
{
    return !a
}

func unaryBangPointer(a: *void?)->bool
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

    Swag.assert(!unaryBangBool(true))
    Swag.assert(unaryBangBool(false))
    Swag.assert(unaryBangInt(0))
    Swag.assert(!unaryBangInt(1))
    Swag.assert(unaryBangPointer(null))
    Swag.assert(!unaryBangPointer(cast(*void) 0x1000'u64))
    Swag.assert(!unaryBangBang(0))
    Swag.assert(unaryBangBang(12))
}
