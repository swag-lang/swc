#global private
using Swag

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func allocateProbe()->*s32
{
    var request: AllocatorRequest
    request.size = #sizeof(s32)
    let allocator = unwrap Swag.getContext().allocator
    allocator.alloc(&request)
    return cast(*s32, unwrap request.address)
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func releaseProbe(pointer: *s32)
{
    var request: AllocatorRequest
    request.address = pointer
    request.size    = #sizeof(s32)
    let allocator = unwrap Swag.getContext().allocator
    allocator.free(&request)
}

#[Swag.NoInline]
func terminalFailure(code: s32) fail
{
    switch code
    {
    case 1:  fail Swag.SystemError{errorID: 1}
    default: fail Swag.SystemError{errorID: 2}
    }
}

#[Swag.NoInline]
func possibleFailure(code: s32) fail
{
    switch code
    {
    case 1:  fail Swag.SystemError{errorID: 1}
    default: return
    }
}

// An explicit early success must survive a later unconditional failure.
#[Swag.NoInline]
func earlySuccess(code: s32) fail
{
    if code == 0 do return
    fail Swag.SystemError{errorID: 3}
}

// Catching every failure makes the helper return successfully.
#[Swag.NoInline]
func caughtFailure(code: s32) fail
{
    discard catch terminalFailure(code)
}

// A non-exhaustive switch leaves the unmatched input as a successful exit.
#[Swag.NoInline]
func incompleteFailure(code: s32) fail
{
    switch code
    {
    case 1: fail Swag.SystemError{errorID: 4}
    }
}

#[Swag.Macro, Swag.CalleeReturn]
func callerReturnProbe(body: #code)
{
    #inject(body)
}

#[Swag.NoInline]
func generatedEarlySuccess(code: s32) fail
{
    callerReturnProbe()
    {
        if code == 0 do return
    }
    fail Swag.SystemError{errorID: 5}
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func afterTerminalFailure(release: bool, code: s32)->s32 fail
{
    let pointer = allocateProbe()
    pointer[] = 42
    if release
    {
        releaseProbe(pointer)
        try terminalFailure(code)
    }
    let result = pointer[]
    releaseProbe(pointer)
    return result
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func afterPossibleFailure(release: bool, code: s32)->s32 fail
{
    let pointer = allocateProbe()
    pointer[] = 42
    if release
    {
        releaseProbe(pointer)
        try possibleFailure(code)
    }
    let result = pointer[]     // swc-expected-warning {{sanity_warn_possible_use_after_free}}
    if not release do releaseProbe(pointer)
    return result
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func afterEarlySuccess(release: bool, code: s32)->s32 fail
{
    let pointer = allocateProbe()
    pointer[] = 42
    if release
    {
        releaseProbe(pointer)
        try earlySuccess(code)
    }
    let result = pointer[]     // swc-expected-warning {{sanity_warn_possible_use_after_free}}
    if not release do releaseProbe(pointer)
    return result
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func afterCaughtFailure(release: bool, code: s32)->s32 fail
{
    let pointer = allocateProbe()
    pointer[] = 42
    if release
    {
        releaseProbe(pointer)
        try caughtFailure(code)
    }
    let result = pointer[]     // swc-expected-warning {{sanity_warn_possible_use_after_free}}
    if not release do releaseProbe(pointer)
    return result
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func afterIncompleteFailure(release: bool, code: s32)->s32 fail
{
    let pointer = allocateProbe()
    pointer[] = 42
    if release
    {
        releaseProbe(pointer)
        try incompleteFailure(code)
    }
    let result = pointer[]     // swc-expected-warning {{sanity_warn_possible_use_after_free}}
    if not release do releaseProbe(pointer)
    return result
}

// An impossible access must not become a proven use-after-free either.
#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func afterDefiniteTerminalFailure(code: s32)->s32 fail
{
    let pointer = allocateProbe()
    releaseProbe(pointer)
    try terminalFailure(code)
    return pointer[]
}

#[Swag.Sanity(.Lifecycle, true), Swag.NoInline]
func afterGeneratedEarlySuccess(release: bool, code: s32)->s32 fail
{
    let pointer = allocateProbe()
    pointer[] = 42
    if release
    {
        releaseProbe(pointer)
        try generatedEarlySuccess(code)
    }
    let result = pointer[]     // swc-expected-warning {{sanity_warn_possible_use_after_free}}
    if not release do releaseProbe(pointer)
    return result
}

#test
{
    expect possibleFailure(0)
    expect earlySuccess(0)
    expect caughtFailure(0)
    expect incompleteFailure(0)
    Swag.require(expect afterTerminalFailure(false, 0) == 42)
    Swag.require(expect afterPossibleFailure(false, 0) == 42)
    Swag.require(expect afterEarlySuccess(false, 0) == 42)
    Swag.require(expect afterCaughtFailure(false, 0) == 42)
    Swag.require(expect afterIncompleteFailure(false, 0) == 42)
    Swag.require(expect afterGeneratedEarlySuccess(false, 0) == 42)
    expect generatedEarlySuccess(0)
    discard catch afterDefiniteTerminalFailure(1)
    discard catch afterTerminalFailure(true, 1)
    discard catch afterTerminalFailure(true, 2)
}
