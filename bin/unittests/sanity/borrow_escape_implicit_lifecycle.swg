#global private

// Definitions only: rejected paths let implicit lifecycle operations retain a local borrow.
struct ImplicitLifecycleStore
{
    callback: (func||())?
}

var implicitLifecycleOwner: ImplicitLifecycleStore
var implicitLifecycleSaved: (func||())?

struct ImplicitLifecycleObserver
{
    marker: s32
}

impl ImplicitLifecycleObserver
{
    mtd opDrop()
    {
        implicitLifecycleSaved = implicitLifecycleOwner.callback
    }
}

#[Swag.NoInline]
func implicitLifecycleCleanupObserver()
{
    var observer: ImplicitLifecycleObserver
}

#[Swag.NoInline]
func implicitLifecycleStoreThroughCleanup(owner: *ImplicitLifecycleStore, callback: func||())
{
    owner.callback = callback
    implicitLifecycleCleanupObserver()
    owner.callback = null
}

func implicitLifecycleRejectCleanupObserver()
{
    var value = 7
    implicitLifecycleStoreThroughCleanup(&implicitLifecycleOwner, func|&value|() { value = 9 })     // swc-expected-error {{sanity_err_borrow_escape}}
}

struct ImplicitLifecyclePure
{
    marker: s32
}

impl ImplicitLifecyclePure
{
    mtd opDrop() { .marker = 0 }
}

#[Swag.NoInline]
func implicitLifecycleCleanupPure()
{
    var local: ImplicitLifecyclePure
}

#[Swag.NoInline]
func implicitLifecycleStoreThroughPureCleanup(owner: *ImplicitLifecycleStore, callback: func||())
{
    owner.callback = callback
    implicitLifecycleCleanupPure()
    owner.callback = null
}

// Cleanup that only writes its own value does not observe the caller's live slot.
func implicitLifecycleAcceptPureCleanup(owner: *ImplicitLifecycleStore)
{
    var value = 7
    implicitLifecycleStoreThroughPureCleanup(owner, func|&value|() { value = 9 })
}

struct ImplicitLifecycleTransferObserver
{
    marker: s32
}

impl ImplicitLifecycleTransferObserver
{
    mtd opDrop() { .marker = 0 }
    mtd opPostCopy() { implicitLifecycleSaved = implicitLifecycleOwner.callback }
    mtd opPostMove() { implicitLifecycleSaved = implicitLifecycleOwner.callback }
}

#[Swag.NoInline]
func implicitLifecycleUnusedTransferHooks()
{
    var value: ImplicitLifecycleTransferObserver
}

#[Swag.NoInline]
func implicitLifecycleStoreWithoutTransfer(owner: *ImplicitLifecycleStore, callback: func||())
{
    owner.callback = callback
    implicitLifecycleUnusedTransferHooks()
    owner.callback = null
}

// Merely declaring this type does not execute either observing transfer hook.
func implicitLifecycleAcceptUnusedTransferHooks()
{
    var value = 7
    implicitLifecycleStoreWithoutTransfer(&implicitLifecycleOwner, func|&value|() { value = 9 })
}

#[Swag.NoInline]
func implicitLifecycleCopyObserver()
{
    var first: ImplicitLifecycleTransferObserver
    var second = first
}

#[Swag.NoInline]
func implicitLifecycleStoreThroughCopy(owner: *ImplicitLifecycleStore, callback: func||())
{
    owner.callback = callback
    implicitLifecycleCopyObserver()
    owner.callback = null
}

func implicitLifecycleRejectCopyObserver()
{
    var value = 7
    implicitLifecycleStoreThroughCopy(&implicitLifecycleOwner, func|&value|() { value = 9 })     // swc-expected-error {{sanity_err_borrow_escape}}
}

#[Swag.NoInline]
func implicitLifecycleMoveObserver()
{
    var first: ImplicitLifecycleTransferObserver
    var second = #move first
}

#[Swag.NoInline]
func implicitLifecycleStoreThroughMove(owner: *ImplicitLifecycleStore, callback: func||())
{
    owner.callback = callback
    implicitLifecycleMoveObserver()
    owner.callback = null
}

func implicitLifecycleRejectMoveObserver()
{
    var value = 7
    implicitLifecycleStoreThroughMove(&implicitLifecycleOwner, func|&value|() { value = 9 })     // swc-expected-error {{sanity_err_borrow_escape}}
}
