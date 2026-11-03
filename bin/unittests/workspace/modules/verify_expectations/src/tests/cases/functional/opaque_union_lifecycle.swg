#global if #command == Swag.CompilerCommand.Test
#global private

using StaticApi

#test
{
    Swag.require(opaqueUnionLifecycleSourceDrop())
}

#test
{
    Swag.require(opaqueUnionLifecycleSourceCopy())
}

#test
{
    Swag.require(opaqueUnionLifecycleSourceMove())
}

#test
{
    opaqueUnionLifecycleReset()
    scope
    {
        var value: OpaqueUnionLifecycleOwner
        value.arm()
        Swag.require(value.isArmed())
    }
    Swag.require(opaqueUnionLifecycleDrops() == 1)
}

#test
{
    opaqueUnionLifecycleReset()
    scope
    {
        var first: OpaqueUnionLifecycleOwner
        first.arm()
        let second = first
        Swag.require(first.isArmed() and second.isArmed())
    }
    Swag.require(opaqueUnionLifecycleCopies() == 1)
    Swag.require(opaqueUnionLifecycleDrops() == 2)
}

#test
{
    opaqueUnionLifecycleReset()
    scope
    {
        var first: OpaqueUnionLifecycleOwner
        first.arm()
        let second = #move first
        Swag.require(not first.isArmed() and second.isArmed())
    }
    Swag.require(opaqueUnionLifecycleMoves() == 1)
    Swag.require(opaqueUnionLifecycleDrops() == 1)
}

#test
{
    let info = cast(const *Swag.TypeInfoStruct, #typeof(OpaqueUnionLifecycleOwner))
    Swag.require(info.opDrop != null)
    Swag.require(info.opPostCopy != null)
    Swag.require(info.opPostMove != null)
}

#test
{
    Swag.require(opaqueUnionLifecycleGenericControl())
}
