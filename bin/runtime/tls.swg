#global namespace Swag

// Releases the copy a thread made of a thread-local global.
private func __releaseTlsVar(value: #null *void)
{
    if value do
        __bootstrapFree(cast(#null [*] void) value)
}

// Allocates one host thread-storage slot for a runtime thread-local global.
func __tlsAlloc()->u64
{
    let slot = __hostTlsAlloc()
    if slot == Swag.U64.Max do
        Swag.panic("too many thread-local globals for the platform", #curlocation)
    return slot
}

func __tlsGetValue(id: u64)->#null *void              => __hostTlsGet(id)
func __tlsSetValue(id: u64, value: #null *void)->bool => __hostTlsSet(id, value)

// Returns the current thread's runtime context, lazily creating it on a thread the runtime has
// never seen (an operating-system-owned callback thread, for example).
func __tlsGetPtr(id: u64, size: u64, init: const *void)->#null *void
{
    var ptr = __tlsGetValue(id)
    if ptr do
        return ptr
    ptr = __bootstrapAlloc(size)
    if !ptr do
        return null
    Swag.memcpy(ptr, init, size)
    if !__tlsSetValue(id, ptr)
    {
        __bootstrapFree(cast(#null [*] void) ptr)
        return null
    }

    // The lazily-created context starts zeroed, which is unusable: the first allocation on such a
    // thread would call through a null allocator interface. Set the slot before installing the
    // allocator so Swag.getContext() inside __runtimeAllocator resolves to this context.
    discard __runtimeAllocator()
    return ptr
}

// Returns the calling thread's copy of a thread-local global, creating it on first access.
//
// `idSlot` is module storage holding the host slot for that global. The copy uses bootstrap
// allocation because the normal Swag allocator itself reaches this path.
func __tlsVarPtr(idSlot: *u64, size: u64, init: const *void)->#null *void
{
    var id = Swag.atomcmpxchg(idSlot, 0, 0)
    if id == 0
    {
        let slot = __hostThreadStorageAlloc(&__releaseTlsVar)
        if !slot do
            Swag.panic("too many thread-local globals for the platform", #curlocation)

        let previous = Swag.atomcmpxchg(idSlot, 0, slot)
        if previous == 0 do
            id = slot
        else
        {
            __hostThreadStorageFree(slot)
            id = previous
        }
    }

    let known = __hostThreadStorageGet(id)
    if known do
        return known

    let created = __bootstrapAlloc(size)
    if !created do
        return null

    Swag.memcpy(created, init, size)
    if !__hostThreadStorageSet(id, created)
    {
        __bootstrapFree(cast(#null [*] void) created)
        return null
    }

    return created
}
