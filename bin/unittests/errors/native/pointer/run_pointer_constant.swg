#global private

using Swag

func runAllocateByte()->*u8
{
    var request: AllocatorRequest
    request.size = 1
    Swag.getContext().allocator!.alloc(&request)
    let buffer = cast(*u8, unwrap request.address)
    buffer[] = 17
    return buffer
}

const RunPointer = #run runAllocateByte()

#main {}

#[Swag.NoInline]
func runReadPointer()->u8 => RunPointer[]     // swc-expected-error {{sema_err_constant_storage_not_static}}

#test { Swag.require(runReadPointer() == 17) }
