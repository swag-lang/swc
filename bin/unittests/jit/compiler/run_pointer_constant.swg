#global private

using Swag

func runAllocateJitByte()->*u8
{
    var request: AllocatorRequest
    request.size = 1
    Swag.getContext().allocator!.alloc(&request)
    let buffer = cast(*u8, unwrap request.address)
    buffer[] = 17
    return buffer
}

const RunJitPointer = #run runAllocateJitByte()

#[Swag.NoInline]
func runReadJitPointer()->u8 => RunJitPointer[]

#test { Swag.require(runReadJitPointer() == 17) }
