#global moduleprivate
using Swag

namespace GenericCloneCodegenSupport
{
    struct(T) BufferBox
    {
        buffer:   [*] T
        count:    u64
        capacity: u64
    }

    impl BufferBox
    {
        mtd reserve(newCapacity: u64)
        {
            if newCapacity == 0
            {
                @free(.buffer)
                .buffer   = null
                .capacity = 0
                return
            }

            let newBuffer = cast([*] T) @realloc(.buffer, newCapacity * #sizeof(T))
            .buffer       = newBuffer
            .capacity     = newCapacity
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
            @free(.buffer)
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
}
