#global if #command == Swag.CompilerCommand.Test
#global private

struct SharedBytesTestAllocator
{
    late backing: Swag.IAllocator
    frees:        u32
}

impl Swag.IAllocator for SharedBytesTestAllocator
{
    mtd impl alloc(request: *Swag.AllocatorRequest) => .backing.alloc(request)
    mtd impl realloc(request: *Swag.AllocatorRequest) => .backing.realloc(request)
    mtd impl free(request: *Swag.AllocatorRequest)
    {
        .frees += 1
        .backing.free(request)
    }
}

// The array allocation is moved once and released only when its last owner is dropped.
#test
{
    let context = Swag.getContext()
    let before  = context.allocator
    var backing = SharedBytesTestAllocator{backing: unwrap before}
    let allocator: Swag.IAllocator = &backing
    context.allocator = allocator
    defer context.allocator = before
    scope
    {
        var bytes: Array!{u8} = [1, 6, 24, 90]
        let address = bytes.toSlice().buffer
        var retained: SharedBytes
        scope
        {
            let source = #move SharedBytes.create(#move bytes)
            retained = source
            Swag.require(source.toSlice().buffer == address and retained.toSlice().buffer == address)
        }

        Swag.require(backing.frees == 0)
        Swag.require(Slice.equals(retained.toSlice(), [1_u8, 6, 24, 90]))
    }

    Swag.require(backing.frees == 2)

    let empty: SharedBytes
    Swag.require(empty.toSlice().count == 0)
}
