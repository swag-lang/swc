#global internal
using Swag

namespace GenericCloneCodegenSupport
{
    func helperFree(buffer: #null [*] void, size: u64, allocator: #null IAllocator = null)
    {
        if !buffer do
            return

        var req: AllocatorRequest
        req.size = size
        req.address = buffer

        let talloc = allocator orelse @getcontext().allocator
        talloc.free(&req)
    }

    func helperRealloc(buffer: #null [*] void, newSize: u64, oldSize: u64, allocator: #null IAllocator = null)->#null [*] void
    {
        var req: AllocatorRequest
        req.address = buffer
        req.size = newSize
        req.oldSize = oldSize

        let talloc = allocator orelse @getcontext().allocator
        talloc.realloc(&req)
        return req.address
    }

    struct(T) BufferBox
    {
        allocator: #null IAllocator
        buffer:   #null [*] T
        count:    u64
        capacity: u64
    }

    impl BufferBox
    {
        mtd reserve(newCapacity: u64)
        {
            if newCapacity <= .capacity do
                return

            .buffer = cast(#null [*] T) helperRealloc(.buffer, newCapacity * #sizeof(T), .capacity * #sizeof(T), .allocator)
            .capacity = newCapacity
        }

        mtd toSlice()->[..] T
        {
            return @mkslice(.buffer, .count)
        }

        mtd add(value: T)
        {
            .buffer[.count] = value
            .count += 1
        }

        mtd free()
        {
            helperFree(.buffer, .capacity * #sizeof(T), .allocator)
            .buffer = null
            .count, .capacity = 0
        }
    }

    struct(T) PtrBox
    {
        values: BufferBox'(*T)
    }

    impl PtrBox
    {
        mtd addNew(value: T)
        {
            let ptr = cast(*T) assume @alloc(#sizeof(T))
            dref ptr = value
            .values.add(ptr)
        }

        mtd clear()
        {
            for item in .values.toSlice() do
                @free(item)
            .values.count = 0
        }
    }
}

#test
{
    var box: GenericCloneCodegenSupport.BufferBox'u32
    box.reserve(4)
    box.add(11)
    box.add(22)

    let values = box.toSlice()
    @assert(values[0] == 11)
    @assert(values[1] == 22)

    box.free()
}

#test
{
    var box: GenericCloneCodegenSupport.PtrBox's32
    box.values.reserve(2)
    box.addNew(7)
    box.addNew(9)

    let values = box.values.toSlice()
    @assert(dref values[0] == 7)
    @assert(dref values[1] == 9)

    box.clear()
    box.values.free()
}