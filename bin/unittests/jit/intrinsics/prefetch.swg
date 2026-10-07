#global private

// Swag.prefetch runs during compile-time execution and leaves every value as it was
#test
{
    func prefetchIsInert()->bool
    {
        var data: [64] u8
        for i in 0 until data.count do
            data[i] = cast(u8, i)

        Swag.prefetch(&data[0])
        Swag.prefetch(&data[32])
        Swag.prefetch(data.buffer + data.count)
        Swag.prefetch(null)

        var sum = 0'u32
        for i in 0 until data.count do
            sum += data[i]
        return sum == 2016
    }

    const V = #run prefetchIsInert()
    #assert(V)
}
