#global if #hastag("MeasureValueBorrow")
#global private
#global #[Swag.Safety(.All, false)]
#global #[Swag.Safety(.ValueBorrow, #hastag("ValueBorrowOn"))]

// Run explicitly with the Win32 module API and MeasureValueBorrow; normal suites omit it.
// Only ValueBorrow changes between samples. Timing is evidence, never a test threshold.
func monotonicTicks()->u64
{
    var counter: u64
    Win32.QueryPerformanceCounter(cast(&counter))
    return counter
}

func monotonicFrequency()->u64
{
    var frequency: u64
    Win32.QueryPerformanceFrequency(cast(&frequency))
    return frequency
}

struct Small { first, second: u64 }
struct Block { values: [128] u64 }

#[Swag.NoInline]
func smallCall(value: Small, output: *u64)->u64
{
    output[] = value.first + 1
    return value.first + value.second
}

#[Swag.NoInline]
func blockCall(value: Block, output: *u64)->u64
{
    var total: u64
    for index in 128 do
        total += value.values[index]
    output[] = total
    return total
}

#test
{
    for 5
    {
        var value:    Small = {17, 19}
        var output:   u64
        var checksum: u64
        let start = monotonicTicks()
        for 2_000_000 do
            checksum += smallCall(value, &output)
        let elapsed = monotonicTicks() - start
        Swag.print("small ticks=", elapsed, " frequency=", monotonicFrequency(), "\n")
        if checksum != 72_000_000 or output != 18
        {
            Swag.panic("small checksum", #curlocation)
        }
    }
}

#test
{
    for 5
    {
        var value: Block
        for index in 128 do value.values[index] = index
        var output:   u64
        var checksum: u64
        let start = monotonicTicks()
        for 50_000 do
            checksum += blockCall(value, &output)
        let elapsed = monotonicTicks() - start
        Swag.print("block ticks=", elapsed, " frequency=", monotonicFrequency(), "\n")
        if checksum != 406_400_000 or output != 8128
        {
            Swag.panic("block checksum", #curlocation)
        }
    }
}
