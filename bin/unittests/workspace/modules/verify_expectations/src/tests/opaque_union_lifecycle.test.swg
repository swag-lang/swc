#global if #command == Swag.CompilerCommand.Test
#global private

using StaticApi

#test
{
    Swag.assert(opaqueUnionLifecycleSourceDrop())
}

#test
{
    Swag.assert(opaqueUnionLifecycleSourceCopy())
}

#test
{
    Swag.assert(opaqueUnionLifecycleSourceMove())
}

#test
{
    opaqueUnionLifecycleReset()
    {
        var value: OpaqueUnionLifecycleOwner
        value.arm()
        Swag.assert(value.isArmed())
    }
    Swag.assert(opaqueUnionLifecycleDrops() == 1)
}

#test
{
    opaqueUnionLifecycleReset()
    {
        var first: OpaqueUnionLifecycleOwner
        first.arm()
        let second = first
        Swag.assert(first.isArmed() and second.isArmed())
    }
    Swag.assert(opaqueUnionLifecycleCopies() == 1)
    Swag.assert(opaqueUnionLifecycleDrops() == 2)
}

#test
{
    opaqueUnionLifecycleReset()
    {
        var first: OpaqueUnionLifecycleOwner
        first.arm()
        let second = #move first
        Swag.assert(not first.isArmed() and second.isArmed())
    }
    Swag.assert(opaqueUnionLifecycleMoves() == 1)
    Swag.assert(opaqueUnionLifecycleDrops() == 1)
}

#test
{
    let info = cast(const *Swag.TypeInfoStruct) #typeof(OpaqueUnionLifecycleOwner)
    Swag.assert(info.opDrop != null)
    Swag.assert(info.opPostCopy != null)
    Swag.assert(info.opPostMove != null)
}

#test
{
    Swag.assert(opaqueUnionLifecycleGenericControl())
}
