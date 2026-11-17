#global private
using Swag

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func allocateWarningProbe()->*s32
{
    var request: AllocatorRequest
    request.size = #sizeof(s32)
    let allocator = unwrap Swag.getContext().allocator
    allocator.alloc(&request)
    return cast(*s32, unwrap request.address)
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func releaseWarningProbe(pointer: *s32)
{
    var request: AllocatorRequest
    request.address = pointer
    request.size    = #sizeof(s32)
    let allocator = unwrap Swag.getContext().allocator
    allocator.free(&request)
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline, Swag.Warning("sanity_warn_possible_use_after_free", .Error)]
func sourceWarningError(release: bool)->s32
{
    let pointer = allocateWarningProbe()
    pointer[] = 42
    if release do releaseWarningProbe(pointer)
    let result = pointer[]     // swc-expected-error {{sanity_warn_possible_use_after_free}}
    if not release do releaseWarningProbe(pointer)
    return result
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline, Swag.Warning("sanity_warn_possible_use_after_free", .Disable)]
func sourceWarningDisable(release: bool)->s32
{
    let pointer = allocateWarningProbe()
    pointer[] = 42
    if release do releaseWarningProbe(pointer)
    let result = pointer[]
    if not release do releaseWarningProbe(pointer)
    return result
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline, Swag.Warning("sanity_warn_possible_use_after_free", .Warning)]
func sourceWarningDefault(release: bool)->s32
{
    let pointer = allocateWarningProbe()
    pointer[] = 42
    if release do releaseWarningProbe(pointer)
    let result = pointer[]     // swc-expected-warning {{sanity_warn_possible_use_after_free}}
    if not release do releaseWarningProbe(pointer)
    return result
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline, Swag.Warning("sanity_warn_possible_use_after_free", .Warning)]
func sourceBlockError(release: bool)->s32
{
    let pointer = allocateWarningProbe()
    pointer[] = 42
    if release do releaseWarningProbe(pointer)
    var result: s32
    #[Swag.Warning("sanity_warn_possible_use_after_free", .Error)]
    {
        result = pointer[]     // swc-expected-error {{sanity_warn_possible_use_after_free}}
    }
    if not release do releaseWarningProbe(pointer)
    return result
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline, Swag.Warning("sanity_warn_possible_use_after_free", .Error)]
func sourceBlockDisable(release: bool)->s32
{
    let pointer = allocateWarningProbe()
    pointer[] = 42
    if release do releaseWarningProbe(pointer)
    var result: s32
    #[Swag.Warning("sanity_warn_possible_use_after_free", .Disable)]
    {
        result = pointer[]
    }
    if not release do releaseWarningProbe(pointer)
    return result
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline, Swag.Warning("sanity_warn_possible_use_after_free", .Error)]
func sourceBlockWarning(release: bool)->s32
{
    let pointer = allocateWarningProbe()
    pointer[] = 42
    if release do releaseWarningProbe(pointer)
    var result: s32
    #[Swag.Warning("sanity_warn_possible_use_after_free", .Warning)]
    {
        result = pointer[]     // swc-expected-warning {{sanity_warn_possible_use_after_free}}
    }
    if not release do releaseWarningProbe(pointer)
    return result
}

// Leaving the block restores the enclosing declaration policy.
#[Swag.Sanity(.Lifecycle, true), Swag.NoInline, Swag.Warning("sanity_warn_possible_use_after_free", .Error)]
func sourceBlockRestore(release: bool)->s32
{
    let pointer = allocateWarningProbe()
    pointer[] = 42
    if release do releaseWarningProbe(pointer)
    #[Swag.Warning("sanity_warn_possible_use_after_free", .Disable)]
    {
        discard pointer[]
    }
    let result = pointer[]     // swc-expected-error {{sanity_warn_possible_use_after_free}}
    if not release do releaseWarningProbe(pointer)
    return result
}

// A deferred body keeps its declaration policy when a nested block returns.
#[Swag.Sanity(.Lifecycle, true), Swag.NoInline, Swag.Warning("sanity_warn_possible_use_after_free", .Error)]
func sourceDeferredError(release: bool)
{
    let pointer = allocateWarningProbe()
    pointer[] = 42
    if release do releaseWarningProbe(pointer)
    defer
    {
        Swag.assert(pointer[] == 42)     // swc-expected-error {{sanity_warn_possible_use_after_free}}
        if not release do releaseWarningProbe(pointer)
    }
    #[Swag.Warning("sanity_warn_possible_use_after_free", .Disable)]
    {
        return
    }
}

#test
{
    sourceDeferredError(false)
    discard sourceBlockRestore(false)
    discard sourceWarningError(false)
    discard sourceWarningDisable(false)
    discard sourceWarningDefault(false)
    discard sourceBlockError(false)
    discard sourceBlockDisable(false)
    discard sourceBlockWarning(false)
}
