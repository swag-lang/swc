#global private

// These definitions are checked without executing their deliberately unsafe paths.
struct ReentrantStoreHolder
{
    callback: (func||())?
    other:    (func||())?
}

var reentrantStoreGlobalHolder: ReentrantStoreHolder
var reentrantStoreSaved:        (func||())?

#[Swag.NoInline]
func reentrantStorePublishGlobal()
{
    reentrantStoreSaved = reentrantStoreGlobalHolder.callback
}

#[Swag.NoInline]
func reentrantStorePublishOwner(owner: *ReentrantStoreHolder)
{
    reentrantStoreSaved = owner.callback
}

// Invoking the live slot can reenter code that retains a copy before it is cleared.
#[Swag.NoInline]
func reentrantStoreInvoke(owner: *ReentrantStoreHolder, callback: func||())
{
    owner.callback = callback
    if owner.callback do
        owner.callback()
    owner.callback = null
}

func reentrantStoreRejectInvocation()
{
    var value = 7
    reentrantStoreInvoke(&reentrantStoreGlobalHolder, func|&value|() { reentrantStorePublishGlobal(); value = 9 })     // swc-expected-error {{sanity_err_borrow_escape}}
}

// A zero-argument call can reach the owner through a global alias.
#[Swag.NoInline]
func reentrantStoreCallGlobalHook(owner: *ReentrantStoreHolder, callback: func||())
{
    owner.callback = callback
    reentrantStorePublishGlobal()
    owner.callback = null
}

func reentrantStoreRejectGlobalHook()
{
    var value = 7
    reentrantStoreCallGlobalHook(&reentrantStoreGlobalHolder, func|&value|() { value = 9 })     // swc-expected-error {{sanity_err_borrow_escape}}
}

// Distinct parameters can designate the same caller-owned storage.
#[Swag.NoInline]
func reentrantStoreCallAliasedOwner(owner: *ReentrantStoreHolder, aliasOwner: *ReentrantStoreHolder, callback: func||())
{
    owner.callback = callback
    reentrantStorePublishOwner(aliasOwner)
    owner.callback = null
}

func reentrantStoreRejectAliasedParameter(owner: *ReentrantStoreHolder)
{
    var value = 7
    reentrantStoreCallAliasedOwner(owner, owner, func|&value|() { value = 9 })     // swc-expected-error {{sanity_err_borrow_escape}}
}

// An alias made before the store still reads the live slot afterward.
#[Swag.NoInline]
func reentrantStoreReadEarlierAlias(owner: *ReentrantStoreHolder, callback: func||())
{
    let aliasOwner = owner
    owner.callback      = callback
    reentrantStoreSaved = aliasOwner.callback
    owner.callback      = null
}

func reentrantStoreRejectEarlierAlias(owner: *ReentrantStoreHolder)
{
    var value = 7
    reentrantStoreReadEarlierAlias(owner, func|&value|() { value = 9 })     // swc-expected-error {{sanity_err_borrow_escape}}
}

// Taking the slot address before the store is another way to retain an alias.
#[Swag.NoInline]
func reentrantStoreReadEarlierSlotAlias(owner: *ReentrantStoreHolder, callback: func||())
{
    let aliasSlot = &owner.callback
    owner.callback      = callback
    reentrantStoreSaved = aliasSlot[]
    owner.callback      = null
}

func reentrantStoreRejectEarlierSlotAlias(owner: *ReentrantStoreHolder)
{
    var value = 7
    reentrantStoreReadEarlierSlotAlias(owner, func|&value|() { value = 9 })     // swc-expected-error {{sanity_err_borrow_escape}}
}

// An indirect call can return an owner alias before the slot becomes live.
#[Swag.NoInline]
func reentrantStoreResolveOwner(owner: *ReentrantStoreHolder)->*ReentrantStoreHolder => owner

#[Swag.NoInline]
func reentrantStoreReadResolvedAlias(resolveOwner: func(*ReentrantStoreHolder)->*ReentrantStoreHolder, owner: *ReentrantStoreHolder, callback: func||())
{
    let aliasOwner = resolveOwner(owner)
    owner.callback      = callback
    reentrantStoreSaved = aliasOwner.callback
    owner.callback      = null
}

func reentrantStoreRejectResolvedAlias(owner: *ReentrantStoreHolder)
{
    var value = 7
    reentrantStoreReadResolvedAlias(&reentrantStoreResolveOwner, owner, func|&value|() { value = 9 })     // swc-expected-error {{sanity_err_borrow_escape}}
}

// Clearing one field does not clear the same source stored in another field.
#[Swag.NoInline]
func reentrantStoreLeaveSecondSlot(owner: *ReentrantStoreHolder, callback: func||())
{
    owner.callback = callback
    owner.other    = callback
    owner.callback = null
}

func reentrantStoreRejectSecondSlot(owner: *ReentrantStoreHolder)
{
    var value = 7
    reentrantStoreLeaveSecondSlot(owner, func|&value|() { value = 9 })     // swc-expected-error {{sanity_err_borrow_escape}}
}

// The same field declaration on another instance is a different slot.
#[Swag.NoInline]
func reentrantStoreClearOtherOwner(owner: *ReentrantStoreHolder, otherOwner: *ReentrantStoreHolder, callback: func||())
{
    owner.callback      = callback
    otherOwner.callback = null
}

func reentrantStoreRejectOtherOwner(owner: *ReentrantStoreHolder, otherOwner: *ReentrantStoreHolder)
{
    var value = 7
    reentrantStoreClearOtherOwner(owner, otherOwner, func|&value|() { value = 9 })     // swc-expected-error {{sanity_err_borrow_escape}}
}

// Defers run in reverse order, so the final cleanup here reinstalls the borrow.
#[Swag.NoInline]
func reentrantStoreReinstallOnExit(owner: *ReentrantStoreHolder, callback: func||())
{
    owner.callback = callback
    defer owner.callback = callback
    defer owner.callback = null
}

func reentrantStoreRejectReverseDefers(owner: *ReentrantStoreHolder)
{
    var value = 7
    reentrantStoreReinstallOnExit(owner, func|&value|() { value = 9 })     // swc-expected-error {{sanity_err_borrow_escape}}
}

struct ReentrantStoreFailure {}

// Failure-only cleanup leaves the normal exit live.
#[Swag.NoInline]
func reentrantStoreClearOnlyOnFailure(owner: *ReentrantStoreHolder, callback: func||(), shouldFail: bool) fail
{
    owner.callback = callback
    defer #fail owner.callback = null
    if shouldFail do
        fail ReentrantStoreFailure{}
}

func reentrantStoreRejectNormalExit(owner: *ReentrantStoreHolder)
{
    var value = 7
    catch reentrantStoreClearOnlyOnFailure(owner, func|&value|() { value = 9 }, false)     // swc-expected-error {{sanity_err_borrow_escape}}
}

// Success-only cleanup leaves the failure exit live.
#[Swag.NoInline]
func reentrantStoreClearOnlyOnSuccess(owner: *ReentrantStoreHolder, callback: func||(), shouldFail: bool) fail
{
    owner.callback = callback
    defer #nofail owner.callback = null
    if shouldFail do
        fail ReentrantStoreFailure{}
}

func reentrantStoreRejectFailureExit(owner: *ReentrantStoreHolder)
{
    var value = 7
    catch reentrantStoreClearOnlyOnSuccess(owner, func|&value|() { value = 9 }, true)     // swc-expected-error {{sanity_err_borrow_escape}}
}

struct ReentrantStoreRestorer
{
    owner:    *ReentrantStoreHolder
    callback: func||()
}

impl ReentrantStoreRestorer
{
    mtd opDrop()
    {
        .owner.callback = .callback
    }
}

// Implicit destruction can restore a borrow after the last explicit clear.
#[Swag.NoInline]
func reentrantStoreRestoreOnDrop(owner: *ReentrantStoreHolder, callback: func||())
{
    var restorer = ReentrantStoreRestorer{owner, callback}
    owner.callback = callback
    owner.callback = null
}

func reentrantStoreRejectImplicitDrop(owner: *ReentrantStoreHolder)
{
    var value = 7
    reentrantStoreRestoreOnDrop(owner, func|&value|() { value = 9 })     // swc-expected-error {{sanity_err_borrow_escape}}
}
