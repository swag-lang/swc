#global internal
using Swag

namespace GenericCloneCodegenSupport
{
    func helperFree(buffer: [*] void, size: u64, allocator: IAllocator = null)
    {
        if !buffer do
            return

        var req: AllocatorRequest
        req.size = size
        req.address = buffer

        let talloc = allocator orelse @getcontext().allocator
        talloc.free(&req)
    }

    func helperRealloc(buffer: [*] void, newSize: u64, oldSize: u64, allocator: IAllocator = null)->[*] void
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
        allocator: IAllocator
        buffer:   [*] T
        count:    u64
        capacity: u64
    }

    impl BufferBox
    {
        mtd reserve(newCapacity: u64)
        {
            if newCapacity <= .capacity do
                return

            .buffer = cast([*] T) helperRealloc(.buffer, newCapacity * #sizeof(T), .capacity * #sizeof(T), .allocator)
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
            let ptr = cast(*T) @alloc(#sizeof(T))
            dref ptr = value
            .values.add(ptr)
        }

        mtd clear()
        {
            foreach item in .values.toSlice() do
                @free(item)
            .values.count = 0
        }
    }

    struct(T) OwnedPtrVisitBox
    {
        first:  *T
        second: *T
        count:  u64
    }

    impl OwnedPtrVisitBox
    {
        #[Swag.Macro]
        mtd(ptr: bool, back: bool) const opVisit(stmt: #code void)
        {
            #if ptr do
                #error("OwnedPtrVisitBox does not expose pointer iteration.")

            #if back
            {
                #macro
                {
                    if #up me.count > 1
                    {
                        let #alias0 = #up me.second
                        let #alias1 = 1'u64
                        #inject(#up stmt)
                    }
                }

                #macro
                {
                    if #up me.count > 0
                    {
                        let #alias0 = #up me.first
                        let #alias1 = 0'u64
                        #inject(#up stmt)
                    }
                }

                return
            }

            #macro
            {
                if #up me.count > 0
                {
                    let #alias0 = #up me.first
                    let #alias1 = 0'u64
                    #inject(#up stmt)
                }
            }

            #macro
            {
                if #up me.count > 1
                {
                    let #alias0 = #up me.second
                    let #alias1 = 1'u64
                    #inject(#up stmt)
                }
            }
        }

        mtd addNew(value: T)
        {
            let ptr = cast(*T) @alloc(#sizeof(T))
            dref ptr = value
            if .count == 0 do
                .first = ptr
            else do
                .second = ptr
            .count += 1
        }

        mtd clearOwned()
        {
            foreach item in me do
                @free(item)
            .first = null
            .second = null
            .count = 0
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

#test
{
    var values: GenericCloneCodegenSupport.OwnedPtrVisitBox's32
    values.addNew(3)
    values.addNew(5)

    @assert(dref values.first == 3)
    @assert(dref values.second == 5)

    values.clearOwned()
    @assert(values.count == 0)
}