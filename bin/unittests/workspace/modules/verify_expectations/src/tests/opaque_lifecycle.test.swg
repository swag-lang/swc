#global if #command == Swag.CompilerCommand.Test
#global private

using StaticApi

#test
{
    Swag.assert(opaqueLifecycleSourceControl() == 1)
}

// An imported value owns cleanup even when only a hidden member declares it.
#test
{
    opaqueLifecycleReset()
    {
        var value: OpaqueLifecycleOwner
        value.arm()
        Swag.assert(value.isArmed())
    }
    Swag.assert(opaqueLifecycleDrops() == 1)
}

#test
{
    opaqueLifecycleReset()
    {
        var first: OpaqueLifecycleOwner
        first.arm()
        var second = first
        Swag.assert(first.isArmed())
        Swag.assert(second.isArmed())
        Swag.assert(opaqueLifecycleCopies() == 1)
    }
    Swag.assert(opaqueLifecycleDrops() == 2)
}

// An explicit public call remains direct; automatic cleanup runs the complete operation.
#test
{
    opaqueLifecycleReset()
    {
        var value: OpaqueLifecycleOrdered
        value.arm()
        value.opDrop()
        Swag.assert(opaqueLifecycleTrace() == 3)
        Swag.assert(opaqueLifecycleDrops() == 0)
    }
    Swag.assert(opaqueLifecycleTrace() == 3321)
    Swag.assert(opaqueLifecycleDrops() == 2)
}

// Members repair their copies before the outer operation, without a second traversal.
#test
{
    opaqueLifecycleReset()
    {
        var first: OpaqueLifecycleOrdered
        first.arm()
        var second = first
        Swag.assert(first.isArmed())
        Swag.assert(second.isArmed())
        Swag.assert(opaqueLifecycleTrace() == 124)
        Swag.assert(opaqueLifecycleCopies() == 2)
    }
    Swag.assert(opaqueLifecycleDrops() == 4)
}

#test
{
    opaqueLifecycleReset()
    {
        var first: OpaqueLifecycleOrdered
        first.arm()
        var second = #move first
        Swag.assert(not first.isArmed())
        Swag.assert(second.isArmed())
        Swag.assert(opaqueLifecycleTrace() == 125)
        Swag.assert(opaqueLifecycleMoves() == 2)
    }
    Swag.assert(opaqueLifecycleDrops() == 2)
}

// NoCopy inherited from a hidden member still permits a transfer.
#test
{
    var first: OpaqueLifecycleNoCopy
    first.arm()
    let second = #move first
    Swag.assert(second.isArmed())
}

#test
{
    opaqueLifecycleReset()
    {
        var values: [2] OpaqueLifecycleOwner
        values[0].arm()
        values[1].arm()
    }
    Swag.assert(opaqueLifecycleDrops() == 2)
}

// Reflection uses the same complete provider callbacks and keeps its init callback.
#test
{
    opaqueLifecycleReset()
    let info = cast(const *Swag.TypeInfoStruct) #typeof(OpaqueLifecycleOwner)
    Swag.assert(info.opInit != null)
    Swag.assert(info.opDrop != null)
    Swag.assert(info.opPostCopy != null)
    Swag.assert(info.opPostMove != null)
    var value: OpaqueLifecycleOwner
    value.arm()
    let drop = info.opDrop
    drop(&value)
    Swag.assert(opaqueLifecycleDrops() == 1)
    let initialize = info.opInit
    initialize(&value)
    Swag.assert(not value.isArmed())
}

func rejectOpaqueInheritedNoCopy()
{
    var first: OpaqueLifecycleNoCopy
    first.arm()
    let second = first     // swc-expected-error {{sema_err_cannot_copy_nocopy}}
    Swag.assert(first.isArmed())
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
