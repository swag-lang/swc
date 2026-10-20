#global private

#[Swag.NoInline]
func scanSwap(values: [*] u64, last: s64, pivot: u64, mutate: bool)->s64
{
    var left  = 0's64
    var right = last
    while values[left] < pivot do
        left += 1
    while values[right] > pivot
    {
        if mutate do
            values[left] += 1
        right -= 1
    }

    if left <= right
    {
        let first = values[left]
        values[left]  = values[right]
        values[right] = first
    }

    return left * 10 + right
}

#test
{
    var values: [6] u64 = [1, 5, 2, 9, 8, 7]
    let positions       = scanSwap(&values[0], 5, 4, false)
    Swag.assert(positions == 12)
    Swag.assert(values == [1, 2, 5, 9, 8, 7])
}

#test
{
    // The second scan changes the cell the first scan compared.
    var values: [6] u64 = [1, 5, 2, 9, 8, 7]
    let positions       = scanSwap(&values[0], 5, 4, true)
    Swag.assert(positions == 12)
    Swag.assert(values == [1, 2, 8, 9, 8, 7])
}

#test
{
    var values: [6] u64 = [1, 2, 3, 4, 5, 6]
    let positions       = scanSwap(&values[0], 5, 4, false)
    Swag.assert(positions == 33)
    Swag.assert(values == [1, 2, 3, 4, 5, 6])
}

#test
{
    var values: [6] u64 = [6, 5, 4, 3, 2, 1]
    let positions       = scanSwap(&values[0], 5, 4, false)
    Swag.assert(positions == 5)
    Swag.assert(values == [1, 5, 4, 3, 2, 6])
}
