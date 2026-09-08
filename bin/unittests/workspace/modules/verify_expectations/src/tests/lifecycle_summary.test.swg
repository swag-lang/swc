#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// The FREES summary has to survive the module boundary: 'Memory.free' reaches
// 'Swag.IAllocator.free' inside 'core', and what the importing module reads is the
// 'Swag.BorrowSummary' the generated API carries. These cases judge the standard
// library's own allocation API, which is what user code actually writes.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let buffer = cast([*] u8) Memory.alloc(16)
    buffer[0] = 1
    Memory.free(buffer, 16)         // swc-expected-note {{sanity_note_pointer_released_here}}
    Swag.assert(buffer[0] == 1)     // swc-expected-error {{sanity_err_use_after_free}}
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let buffer = cast([*] u8) Memory.alloc(16)
    Memory.free(buffer, 16)         // swc-expected-note {{sanity_note_pointer_released_here}}
    Memory.free(buffer, 16)         // swc-expected-error {{sanity_err_double_free}}
}

// The copy names the same block across the boundary too.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let buffer = cast([*] u8) Memory.alloc(16)
    let same   = buffer
    Memory.free(buffer, 16)         // swc-expected-note {{sanity_note_pointer_released_here}}
    Swag.assert(same[0] == 0)       // swc-expected-error {{sanity_err_use_after_free}}
}

// Allocating, using and releasing once is what correct code looks like.
#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let buffer = cast([*] u8) Memory.alloc(16)
    buffer[0] = 7
    let value = buffer[0]
    Memory.free(buffer, 16)
    Swag.assert(value == 7)
}

// Control: the same fault with the release helper written here, so a silence above can
// be attributed to the imported summary rather than to the module.
#[Swag.Sanity(.Lifecycle, true)]
func localFree(ptr: *void, size: u64)
{
    var req: Swag.AllocatorRequest
    req.address = ptr
    req.size    = size
    let allocItf = Swag.getContext().allocator!
    allocItf.free(&req)
}

#[Swag.Sanity(.Lifecycle, true)]
#test
{
    let buffer = cast([*] u8) Memory.alloc(16)
    buffer[0] = 3
    localFree(buffer, 16)           // swc-expected-note {{sanity_note_pointer_released_here}}
    Swag.assert(buffer[0] == 3)     // swc-expected-error {{sanity_err_use_after_free}}
}
