#global private
#global #[Swag.Safety(.Overflow, false)]

// Keep more integer values live than the register file holds while variable
// shifts and products require fixed registers. Check every resulting value.
#[Swag.Optimize(true), Swag.NoInline]
func transform(values: [*] u64, rounds: u32)
{
    var v0  = values[0]
    var v1  = values[1]
    var v2  = values[2]
    var v3  = values[3]
    var v4  = values[4]
    var v5  = values[5]
    var v6  = values[6]
    var v7  = values[7]
    var v8  = values[8]
    var v9  = values[9]
    var v10 = values[10]
    var v11 = values[11]
    var v12 = values[12]
    var v13 = values[13]
    for rounds
    {
        v0  = ((v0 << (v1 & 63)) ^ v2) * (v3 | 1)
        v1  = ((v1 << (v2 & 63)) ^ v3) * (v4 | 1)
        v2  = ((v2 << (v3 & 63)) ^ v4) * (v5 | 1)
        v3  = ((v3 << (v4 & 63)) ^ v5) * (v6 | 1)
        v4  = ((v4 << (v5 & 63)) ^ v6) * (v7 | 1)
        v5  = ((v5 << (v6 & 63)) ^ v7) * (v8 | 1)
        v6  = ((v6 << (v7 & 63)) ^ v8) * (v9 | 1)
        v7  = ((v7 << (v8 & 63)) ^ v9) * (v10 | 1)
        v8  = ((v8 << (v9 & 63)) ^ v10) * (v11 | 1)
        v9  = ((v9 << (v10 & 63)) ^ v11) * (v12 | 1)
        v10 = ((v10 << (v11 & 63)) ^ v12) * (v13 | 1)
        v11 = ((v11 << (v12 & 63)) ^ v13) * (v0 | 1)
        v12 = ((v12 << (v13 & 63)) ^ v0) * (v1 | 1)
        v13 = ((v13 << (v0 & 63)) ^ v1) * (v2 | 1)
    }
    values[0]  = v0
    values[1]  = v1
    values[2]  = v2
    values[3]  = v3
    values[4]  = v4
    values[5]  = v5
    values[6]  = v6
    values[7]  = v7
    values[8]  = v8
    values[9]  = v9
    values[10] = v10
    values[11] = v11
    values[12] = v12
    values[13] = v13
}

#[Swag.Optimize(false), Swag.NoInline]
func reference(values: [*] u64, rounds: u32)
{
    for rounds
    {
        for i in 14 do
            values[i] = ((values[i] << (values[(i + 1) % 14] & 63)) ^ values[(i + 2) % 14]) * (values[(i + 3) % 14] | 1)
    }
}

#test
{
    for seed in [0'u64, 1, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    {
        for rounds in 9'u32
        {
            var actual, expected: [14] u64
            for i in 14
            {
                actual[i]   = seed ^ (cast(u64) i * 0x123456789ABCDEF'u64)
                expected[i] = actual[i]
            }
            transform(&actual[0], rounds)
            reference(&expected[0], rounds)
            for i in 14 do
                Swag.assert(actual[i] == expected[i])
        }
    }
}
