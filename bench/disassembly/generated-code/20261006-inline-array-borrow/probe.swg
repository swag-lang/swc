#global private

#[Swag.Inline]
func choose(values: [16] u64, index: u32)->u64 => values[index] + values[15 - index]

#[Swag.NoInline, Swag.PrintMicro("post-emit")]
func wrapper(source: *[16] u64, index: u32)->u64
{
    let values = source[]
    return choose(values, index)
}

#test
{
    var values: [16] u64
    for i in 16 do
        values[i] = i * 17
    for i in 16'u32 do
        Swag.assert(wrapper(&values, i) == 255)
}
