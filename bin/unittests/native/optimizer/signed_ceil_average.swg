#global private

#[Swag.NoInline]
func average(values: const [*]s32, index: u64)->s32
{
    let left  = values[index]
    let right = values[index + 1]
    return (left | right) - ((left ^ right) >> 1)
}

#test
{
    let values = [-5's32, -4, -5, 4, -4, 5, -7, -7, 8, 9, -2000000000, 2000000000]
    let results = [-4's32, 0, 1, -7, 9, 0]
    for result, index in results do
        Swag.assert(average(&values[0], index * 2) == result)
}
