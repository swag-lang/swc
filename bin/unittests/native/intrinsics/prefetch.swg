#global private

#[Swag.NoInline]
func prefetchRow(row: const [*] u8, count: u64)->u32
{
    var sum = 0'u32
    for i in 0 until count
    {
        // A row ahead may lie past the end of the buffer: the hint never faults.
        Swag.prefetch(row + i + 64)
        sum += row[i]
    }
    return sum
}

// Swag.prefetch accepts any pointer, including null and one past the end, and changes nothing
#test
{
    var data: [16] u32
    for i in 0 until data.count do
        data[i] = cast(u32) i

    Swag.prefetch(&data[0])
    Swag.prefetch(data.buffer + data.count)
    Swag.prefetch(null)

    let missing: *u32? = null
    Swag.prefetch(missing)

    for i in 0 until data.count do
        Swag.assert(data[i] == cast(u32) i)
}

// A prefetch inside a loop neither disturbs the reads around it nor faults past the end
#test
{
    var bytes: [100] u8
    for i in 0 until bytes.count do
        bytes[i] = cast(u8) ((i * 3) % 251)

    var expected = 0'u32
    for i in 0 until bytes.count do
        expected += bytes[i]
    Swag.assert(prefetchRow(bytes.buffer, bytes.count) == expected)
}
