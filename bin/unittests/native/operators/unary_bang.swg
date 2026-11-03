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

    Swag.require(not unaryBangBool(true))
    Swag.require(unaryBangBool(false))
    Swag.require(unaryBangInt(0))
    Swag.require(not unaryBangInt(1))
    Swag.require(unaryBangPointer(null))
    Swag.require(not unaryBangPointer(cast(*void, 0x1000'u64)))
    Swag.require(not unaryBangBang(0))
    Swag.require(unaryBangBang(12))
}
