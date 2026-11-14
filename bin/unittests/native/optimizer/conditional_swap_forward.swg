#global private

#[Swag.Optimize(true), Swag.NoInline]
func reorder(values: [*] u64, first, second, next: u64)->u64
{
    if values[first] > values[second]
    {
        let temporary = values[first]
        values[first]  = values[second]
        values[second] = temporary
    }
    let other = values[next]
    return values[first] ^ other
}

#test
{
    for input in [[100'u64, 17, 23], [0'u64, 17, 23],
                  [0x8000000000000000'u64, 0xFFFFFFFFFFFFFFFF, 17]]
    {
        for first in 3'u64
        {
            for second in 3'u64
            {
                var actual   = input
                var expected = input
                if input[first] > input[second]
                {
                    expected[first]  = input[second]
                    expected[second] = input[first]
                }
                Swag.require(reorder(&actual[0], first, second, 2) == (expected[first] ^ expected[2]))
                for i in 3 do
                    Swag.require(actual[i] == expected[i])
            }
        }
    }
}
