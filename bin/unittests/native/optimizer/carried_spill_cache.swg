#global private
#global #[Swag.Safety(.Overflow, false)]

// Changing branch arms and early exits must preserve every carried value,
// including when the integer register pressure forces private spill homes.
#[Swag.Optimize(true), Swag.NoInline]
func transform(values: [*] u64, rounds, stop: u32)->u64
{
    var v0 = values[0]
    var v1 = values[1]
    var v2 = values[2]
    var v3 = values[3]
    var v4 = values[4]
    var v5 = values[5]
    var v6 = values[6]
    var v7 = values[7]
    var v8 = values[8]
    var v9 = values[9]
    var v10 = values[10]
    var v11 = values[11]
    var v12 = values[12]
    var v13 = values[13]
    for i in rounds
    {
        if i == stop do
            return v0 ^ v1 ^ v2 ^ v3 ^ v4 ^ v5 ^ v6 ^ v7 ^ v8 ^ v9 ^ v10 ^ v11 ^ v12 ^ v13
        if i & 1
        {
            v0 = ((v0 << (v1 & 63)) ^ v2) * (v3 | 1)
            v1 = ((v1 << (v2 & 63)) ^ v3) * (v4 | 1)
            v2 = ((v2 << (v3 & 63)) ^ v4) * (v5 | 1)
            v3 = ((v3 << (v4 & 63)) ^ v5) * (v6 | 1)
            v4 = ((v4 << (v5 & 63)) ^ v6) * (v7 | 1)
            v5 = ((v5 << (v6 & 63)) ^ v7) * (v8 | 1)
            v6 = ((v6 << (v7 & 63)) ^ v8) * (v9 | 1)
            v7 = ((v7 << (v8 & 63)) ^ v9) * (v10 | 1)
            v8 = ((v8 << (v9 & 63)) ^ v10) * (v11 | 1)
            v9 = ((v9 << (v10 & 63)) ^ v11) * (v12 | 1)
            v10 = ((v10 << (v11 & 63)) ^ v12) * (v13 | 1)
            v11 = ((v11 << (v12 & 63)) ^ v13) * (v0 | 1)
            v12 = ((v12 << (v13 & 63)) ^ v0) * (v1 | 1)
            v13 = ((v13 << (v0 & 63)) ^ v1) * (v2 | 1)
        }
        else
        {
            v0 += (v1 ^ v2) + i
            v1 += (v2 ^ v3) + i
            v2 += (v3 ^ v4) + i
            v3 += (v4 ^ v5) + i
            v4 += (v5 ^ v6) + i
            v5 += (v6 ^ v7) + i
            v6 += (v7 ^ v8) + i
            v7 += (v8 ^ v9) + i
            v8 += (v9 ^ v10) + i
            v9 += (v10 ^ v11) + i
            v10 += (v11 ^ v12) + i
            v11 += (v12 ^ v13) + i
            v12 += (v13 ^ v0) + i
            v13 += (v0 ^ v1) + i
        }
        if i + 1 == stop do
            return v0 + v1 + v2 + v3 + v4 + v5 + v6 + v7 + v8 + v9 + v10 + v11 + v12 + v13
    }
    return v0 ^ v1 ^ v2 ^ v3 ^ v4 ^ v5 ^ v6 ^ v7 ^ v8 ^ v9 ^ v10 ^ v11 ^ v12 ^ v13
}

#[Swag.Optimize(false), Swag.NoInline]
func reference(values: [*] u64, rounds, stop: u32)->u64
{
    var state: [14] u64
    for i in 14 do
        state[i] = values[i]
    for i in rounds
    {
        if i == stop
        {
            var result = 0'u64
            for value in state do
                result ^= value
            return result
        }
        if i & 1
        {
            for j in 14 do
                state[j] = ((state[j] << (state[(j + 1) % 14] & 63)) ^ state[(j + 2) % 14]) * (state[(j + 3) % 14] | 1)
        }
        else
        {
            for j in 14 do
                state[j] += (state[(j + 1) % 14] ^ state[(j + 2) % 14]) + i
        }
        if i + 1 == stop
        {
            var result = 0'u64
            for value in state do
                result += value
            return result
        }
    }
    var result = 0'u64
    for value in state do
        result ^= value
    return result
}

#test
{
    for seed in [0'u64, 1, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    {
        var values: [14] u64
        for i in 14 do
            values[i] = seed ^ (cast(u64) i * 0x123456789ABCDEF'u64)
        for rounds in 12'u32
        {
            for stop in 14'u32 do
                Swag.assert(transform(&values[0], rounds, stop) == reference(&values[0], rounds, stop))
        }
    }
}
