#global private

func unaryBangBool(a: bool)->bool
{
    return not a
}

func unaryBangInt(a: s32)->bool
{
    return not a
}

func unaryBangPointer(a: *void?)->bool
{
    return not a
}

func unaryBangBang(a: s32)->bool
{
    return not (not a)
}

#test
{
    #assert(#typeof(unaryBangBool(true)) == bool)
    #assert(#typeof(unaryBangInt(0)) == bool)
    #assert(#typeof(unaryBangPointer(null)) == bool)

    Swag.assert(not unaryBangBool(true))
    Swag.assert(unaryBangBool(false))
    Swag.assert(unaryBangInt(0))
    Swag.assert(not unaryBangInt(1))
    Swag.assert(unaryBangPointer(null))
    Swag.assert(not unaryBangPointer(cast(*void) 0x1000'u64))
    Swag.assert(not unaryBangBang(0))
    Swag.assert(unaryBangBang(12))
}
