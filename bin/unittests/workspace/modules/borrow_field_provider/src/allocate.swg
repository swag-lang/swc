#global public

using Swag

func allocate(size: u64)->*void
{
    var req: AllocatorRequest
    req.size = size
    Swag.getContext().allocator!.alloc(&req)
    return unwrap req.address
}
