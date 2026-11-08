#global private

using Swag

struct RunOwnedBytes { late buffer: *u8 }

func runMakeOwnedBytes()->RunOwnedBytes
{
    var request: AllocatorRequest
    request.size = 1
    Swag.getContext().allocator!.alloc(&request)
    let buffer = cast(*u8, unwrap request.address)
    buffer[] = 17
    return RunOwnedBytes{buffer}
}

const RunOwned = #run runMakeOwnedBytes()

// The heap pointer belongs to the compile-time process, not the native image.
func runReadOwned()->u8 => RunOwned.buffer[]     // swc-expected-error {{sema_err_constant_storage_not_static}}

#test { discard runReadOwned() }
