#global private
#global #[Swag.Warning("sanity_warn_possible_use_after_free", .Error)]
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

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func sourceFileError(release: bool)->s32
{
    let pointer = allocateWarningProbe()
    pointer[] = 42
    if release do releaseWarningProbe(pointer)
    let result = pointer[]     // swc-expected-error {{sanity_warn_possible_use_after_free}}
    if not release do releaseWarningProbe(pointer)
    return result
}

#test
{
    discard sourceFileError(false)
}
