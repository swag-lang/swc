#global private

// The right child is read only when present. Both its selected index and value
// survive the comparison, including an equal pair and the one-child edge.
#[Swag.Optimize(true), Swag.NoInline]
func siftOnce(values: [*] u64, current, left, count: u64)->u64
{
    let right  = left + 1
    var picked = left
    if right < count and values[right] < values[left] do
        picked = right
    if values[current] <= values[picked] do
        return picked
    let value = values[picked]
    values[picked]  = values[current]
    values[current] = value
    return picked
}

#test
{
    for input in [[100'u64, 30, 20], [100'u64, 20, 30], [10'u64, 20, 30],
                  [0xFFFFFFFFFFFFFFFF'u64, 0, 0xFFFFFFFFFFFFFFFF],
                  [0xFFFFFFFFFFFFFFFF'u64, 0xFFFFFFFFFFFFFFFF, 0], [3'u64, 3, 3]]
    {
        for count in [2'u64, 3]
        {
            var actual   = input
            var expected = input
            let picked   = count == 3 and input[2] < input[1] ? 2'u64 : 1'u64
            if input[0] > input[picked]
            {
                expected[0]      = input[picked]
                expected[picked] = input[0]
            }
            Swag.require(siftOnce(&actual[0], 0, 1, count) == picked)
            for i in 3 do
                Swag.require(actual[i] == expected[i])
        }
    }

    var single = [50'u64, 7]
    Swag.require(siftOnce(&single[0], 0, 1, 2) == 1)
    Swag.require(single[0] == 7 and single[1] == 50)
}
