#global private

struct ClearedStoreSlot
{
    value: *s32?
}

struct ClearedStoreSignal
{
    value: u64
}

#[Swag.NoInline]
func clearedStoreDirect(slot: *ClearedStoreSlot, value: *s32)
{
    slot.value = value
    slot.value = null
}

#[Swag.NoInline]
func clearedStoreForward(slot: *ClearedStoreSlot, value: *s32)
{
    clearedStoreDirect(slot, value)
}

#[Swag.NoInline]
func clearedStoreDeferred(slot: *ClearedStoreSlot, value: *s32)
{
    defer slot.value = null
    slot.value = value
    return
}

#[Swag.NoInline]
func clearedStoreNestedDeferred(slot: *ClearedStoreSlot, value: *s32)
{
    defer
    {
        defer slot.value = null
        slot.value = value
    }
    slot.value = value
}

#[Swag.NoInline]
func clearedStoreBranches(slot: *ClearedStoreSlot, value: *s32, early: bool)
{
    slot.value = value
    if early
    {
        slot.value = null
        return
    }
    slot.value = null
}

#[Swag.NoInline]
func clearedStoreReadSignal(signal: *ClearedStoreSignal)->u64 => signal.value

// A scalar-only direct call cannot publish the live slot through another formal.
#[Swag.NoInline]
func clearedStorePolling(slot: *ClearedStoreSlot, value: *s32, signal: *ClearedStoreSignal)
{
    slot.value = value
    while clearedStoreReadSignal(signal) != 0 {}
    slot.value = null
}

#[Swag.NoInline]
func clearedStoreBeforeFailure(slot: *ClearedStoreSlot, value: *s32) fail
{
    slot.value = value
    slot.value = null
    fail 7
}

func clearedStoreCaller(slot: *ClearedStoreSlot, signal: *ClearedStoreSignal)
{
    var value = 7
    clearedStoreDirect(slot, &value)
    clearedStoreForward(slot, &value)
    clearedStoreDeferred(slot, &value)
    clearedStoreNestedDeferred(slot, &value)
    clearedStoreBranches(slot, &value, true)
    clearedStoreBranches(slot, &value, false)
    clearedStorePolling(slot, &value, signal)
    catch clearedStoreBeforeFailure(slot, &value)
}

#test
{
    var slot:   ClearedStoreSlot
    var signal: ClearedStoreSignal
    clearedStoreCaller(&slot, &signal)
    Swag.assert(slot.value == null)
}

// An early exit leaves the caller-owned destination holding the frame borrow.
#[Swag.NoInline]
func clearedStoreEarlyReturn(slot: *ClearedStoreSlot, value: *s32, early: bool)
{
    slot.value = value
    if early do
        return
    slot.value = null
}

#[Swag.NoInline]
func clearedStoreEarlyFailure(slot: *ClearedStoreSlot, value: *s32, failed: bool) fail
{
    slot.value = value
    if failed do
        fail 7
    slot.value = null
}

#[Swag.NoInline]
func clearedStoreLoopReturn(slot: *ClearedStoreSlot, value: *s32, early: bool)
{
    slot.value = value
    while early
    {
        return
    }
    slot.value = null
}

func clearedStoreRejectExits(slot: *ClearedStoreSlot, condition: bool)
{
    var value = 7
    clearedStoreEarlyReturn(slot, &value, condition)            // swc-expected-error {{sanity_err_borrow_escape}}
    catch clearedStoreEarlyFailure(slot, &value, condition)     // swc-expected-error {{sanity_err_borrow_escape}}
    clearedStoreLoopReturn(slot, &value, condition)             // swc-expected-error {{sanity_err_borrow_escape}}
}

var clearedStoreSaved: *s32?

// Clearing the original slot never cancels a copy published elsewhere.
#[Swag.NoInline]
func clearedStorePublishedCopy(slot: *ClearedStoreSlot, value: *s32)
{
    slot.value        = value
    clearedStoreSaved = slot.value
    slot.value        = null
}

func clearedStoreRejectPublishedCopy(slot: *ClearedStoreSlot)
{
    var value = 7
    clearedStorePublishedCopy(slot, &value)     // swc-expected-error {{sanity_err_borrow_escape}}
}

#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func clearedStoreGuardedIncrement(value: u8)->u8 => value + 1

#[Swag.NoInline]
func clearedStoreGuardedCall(slot: *ClearedStoreSlot, value: *s32, number: u8)->u8
{
    slot.value = value
    let result = clearedStoreGuardedIncrement(number)
    slot.value = null
    return result
}

#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func clearedStoreDirectGuard(slot: *ClearedStoreSlot, value: *s32, number: u8)->u8
{
    slot.value = value
    let result = number + 1
    slot.value = null
    return result
}

#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func clearedStoreWrapped(slot: *ClearedStoreSlot, value: *s32, number: u8)->u8
{
    slot.value = value
    let result = number + #wrap 1
    slot.value = null
    return result
}

// A returning panic hook can publish the slot before the final clear.
func clearedStoreRejectSafetyHook(slot: *ClearedStoreSlot, number: u8)
{
    var value = 7
    discard clearedStoreGuardedCall(slot, &value, number)     // swc-expected-error {{sanity_err_borrow_escape}}
    discard clearedStoreDirectGuard(slot, &value, number)     // swc-expected-error {{sanity_err_borrow_escape}}
}

func clearedStoreAcceptWrap(slot: *ClearedStoreSlot)->u8
{
    var value = 7
    return clearedStoreWrapped(slot, &value, 255)
}

#test
{
    var slot: ClearedStoreSlot
    Swag.assert(clearedStoreAcceptWrap(&slot) == 0)
    Swag.assert(slot.value == null)
}
