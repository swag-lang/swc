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

#[Swag.Sanity(.Lifecycle, true), Swag.Inline, Swag.Warning("sanity_warn_possible_use_after_free", .Error)]
func inlineDefinitionError(release: bool)->s32
{
    let pointer = allocateWarningProbe()
    pointer[] = 42
    if release do releaseWarningProbe(pointer)
    let result = pointer[]     // swc-expected-error {{sanity_warn_possible_use_after_free}}
    if not release do releaseWarningProbe(pointer)
    return result
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline, Swag.Warning("sanity_warn_possible_use_after_free", .Disable)]
func callerDefinitionError(release: bool)->s32 => inlineDefinitionError(release)

#[Swag.Sanity(.Lifecycle, true), Swag.Inline, Swag.Warning("sanity_warn_possible_use_after_free", .Warning)]
func inlineDefinitionWarning(release: bool)->s32
{
    let pointer = allocateWarningProbe()
    pointer[] = 42
    if release do releaseWarningProbe(pointer)
    let result = pointer[]     // swc-expected-warning {{sanity_warn_possible_use_after_free}}
    if not release do releaseWarningProbe(pointer)
    return result
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline, Swag.Warning("sanity_warn_possible_use_after_free", .Error)]
func callerDefinitionWarning(release: bool)->s32 => inlineDefinitionWarning(release)

#[Swag.Sanity(.Lifecycle, true), Swag.Inline, Swag.Warning("sanity_warn_possible_use_after_free", .Disable)]
func inlineDefinitionDisable(release: bool)->s32
{
    let pointer = allocateWarningProbe()
    pointer[] = 42
    if release do releaseWarningProbe(pointer)
    let result = pointer[]
    if not release do releaseWarningProbe(pointer)
    return result
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline, Swag.Warning("sanity_warn_possible_use_after_free", .Error)]
func callerDefinitionDisable(release: bool)->s32 => inlineDefinitionDisable(release)

// Substituted arguments keep the call site's policy, not the inline callee's.
#[Swag.Inline, Swag.Warning("sanity_warn_possible_use_after_free", .Disable)]
func inlineArgumentIdentity(value: s32)->s32 => value

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline, Swag.Warning("sanity_warn_possible_use_after_free", .Error)]
func callerArgumentError(release: bool)->s32
{
    let pointer = allocateWarningProbe()
    pointer[] = 42
    if release do releaseWarningProbe(pointer)
    let result = inlineArgumentIdentity(pointer[])     // swc-expected-error {{sanity_warn_possible_use_after_free}}
    if not release do releaseWarningProbe(pointer)
    return result
}

#test
{
    discard callerArgumentError(false)
    discard callerDefinitionError(false)
    discard callerDefinitionWarning(false)
    discard callerDefinitionDisable(false)
}
