#global private

struct GenericResizeTracked
{
    value: s32 = 1
}

struct(T) GenericResizeBuffer
{
    buffer:   [*] T
    count:    u64
    capacity: u64
}

impl GenericResizeBuffer
{
    mtd reserve(newCapacity: u64)
    {
        .capacity = newCapacity
    }

    mtd resize(newCount: u64)
    {
        if newCount == .count do
            return
        if newCount > .count
        {
            .reserve(newCount)
            @init(.buffer + .count, newCount - .count)
        }
        else
        {
            @drop(.buffer + newCount, .count - newCount)
        }

        .count = newCount
    }
}

#test
{
    var buffer: GenericResizeBuffer'GenericResizeTracked
    buffer.resize(0)
    @assert(buffer.count == 0)
}
