#global if #command == Swag.CompilerCommand.Test
#global private

using StaticApi

#test
{
    Swag.require(opaqueLifecycleSourceControl() == 1)
}

// An imported value owns cleanup even when only a hidden member declares it.
#test
{
    opaqueLifecycleReset()
    scope
    {
        var value: OpaqueLifecycleOwner
        value.arm()
        Swag.require(value.isArmed())
    }
    Swag.require(opaqueLifecycleDrops() == 1)
}

#test
{
    opaqueLifecycleReset()
    scope
    {
        var first: OpaqueLifecycleOwner
        first.arm()
        var second = first
        Swag.require(first.isArmed())
        Swag.require(second.isArmed())
        Swag.require(opaqueLifecycleCopies() == 1)
    }
    Swag.require(opaqueLifecycleDrops() == 2)
}

// An explicit public call remains direct; automatic cleanup runs the complete operation.
#test
{
    opaqueLifecycleReset()
    scope
    {
        var value: OpaqueLifecycleOrdered
        value.arm()
        value.opDrop()
        Swag.require(opaqueLifecycleTrace() == 3)
        Swag.require(opaqueLifecycleDrops() == 0)
    }
    Swag.require(opaqueLifecycleTrace() == 3321)
    Swag.require(opaqueLifecycleDrops() == 2)
}

// Members repair their copies before the outer operation, without a second traversal.
#test
{
    opaqueLifecycleReset()
    scope
    {
        var first: OpaqueLifecycleOrdered
        first.arm()
        var second = first
        Swag.require(first.isArmed())
        Swag.require(second.isArmed())
        Swag.require(opaqueLifecycleTrace() == 124)
        Swag.require(opaqueLifecycleCopies() == 2)
    }
    Swag.require(opaqueLifecycleDrops() == 4)
}

#test
{
    opaqueLifecycleReset()
    scope
    {
        var first: OpaqueLifecycleOrdered
        first.arm()
        var second = #move first
        Swag.require(not first.isArmed())
        Swag.require(second.isArmed())
        Swag.require(opaqueLifecycleTrace() == 125)
        Swag.require(opaqueLifecycleMoves() == 2)
    }
    Swag.require(opaqueLifecycleDrops() == 2)
}

// NoCopy inherited from a hidden member still permits a transfer.
#test
{
    var first: OpaqueLifecycleNoCopy
    first.arm()
    let second = #move first
    Swag.require(second.isArmed())
}

#test
{
    opaqueLifecycleReset()
    scope
    {
        var values: [2] OpaqueLifecycleOwner
        values[0].arm()
        values[1].arm()
    }
    Swag.require(opaqueLifecycleDrops() == 2)
}

// Reflection uses the same complete provider callbacks and keeps its init callback.
#test
{
    opaqueLifecycleReset()
    let info = cast(const *Swag.TypeInfoStruct, #typeof(OpaqueLifecycleOwner))
    Swag.require(info.opInit != null)
    Swag.require(info.opDrop != null)
    Swag.require(info.opPostCopy != null)
    Swag.require(info.opPostMove != null)
    var value: OpaqueLifecycleOwner
    value.arm()
    let drop = info.opDrop
    drop(&value)
    Swag.require(opaqueLifecycleDrops() == 1)
    let initialize = info.opInit
    initialize(&value)
    Swag.require(not value.isArmed())
}

func rejectOpaqueInheritedNoCopy()
{
    var first: OpaqueLifecycleNoCopy
    first.arm()
    let second = first     // swc-expected-error {{sema_err_cannot_copy_nocopy}}
    Swag.require(first.isArmed())
}

// The only call made by this function is the imported, hidden automatic cleanup.
#[Swag.NoInline]
func observeThroughOpaqueCleanup()
{
    var value: OpaqueLifecycleObserver
}

#[Swag.NoInline]
func clearAfterOpaqueCleanup(holder: *DepBorrowContainer, value: *s32)
{
    holder.slot = value
    observeThroughOpaqueCleanup()
    holder.slot = null
}

func rejectOpaqueCleanupObservation(holder: *DepBorrowContainer)
{
    depBorrowSetObservedOwner(holder)
    var value = 7
    clearAfterOpaqueCleanup(holder, &value)     // swc-expected-error {{sanity_err_borrow_escape}}
}
