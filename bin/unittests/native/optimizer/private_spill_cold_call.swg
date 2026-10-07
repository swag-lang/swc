#global private
#global #[Swag.Safety(.Overflow, false)]

// The call may change source data, but the twelve value snapshots must survive.
// Its floating result must also survive restoration of any cached integer homes.
#[Swag.NoInline]
func cold(values: [*] u64, index: u64)->f64
{
    values[index % 12] ^= 0x123456789ABCDEF0
    let x = cast(f64) (values[index % 12] & 127)
    return (x * x + 3.0 * x) + 7.0
}

#[Swag.Optimize(true), Swag.NoInline]
func scan(source: [*] u64, rounds, mask: u64)->u64
{
    let v0  = source[0]
    let v1  = source[1]
    let v2  = source[2]
    let v3  = source[3]
    let v4  = source[4]
    let v5  = source[5]
    let v6  = source[6]
    let v7  = source[7]
    let v8  = source[8]
    let v9  = source[9]
    let v10 = source[10]
    let v11 = source[11]
    var sum = 0'u64
    for i in rounds
    {
        sum += ((v0 ^ v1) + (v2 ^ v3) + (v4 ^ v5) + (v6 ^ v7) + (v8 ^ v9) + (v10 ^ v11)) * (i + 1)
        if i & mask == 0 do
            sum ^= cast(u64) cold(source, i)
        sum = (sum << 3) ^ (sum >> 61) ^ v0 ^ v3 ^ v6 ^ v9
    }
    return sum + v1 + v4 + v7 + v10
}

#[Swag.Optimize(false), Swag.NoInline]
func reference(source: [*] u64, rounds, mask: u64)->u64
{
    let v0  = source[0]
    let v1  = source[1]
    let v2  = source[2]
    let v3  = source[3]
    let v4  = source[4]
    let v5  = source[5]
    let v6  = source[6]
    let v7  = source[7]
    let v8  = source[8]
    let v9  = source[9]
    let v10 = source[10]
    let v11 = source[11]
    var sum = 0'u64
    for i in rounds
    {
        sum += ((v0 ^ v1) + (v2 ^ v3) + (v4 ^ v5) + (v6 ^ v7) + (v8 ^ v9) + (v10 ^ v11)) * (i + 1)
        if i & mask == 0 do
            sum ^= cast(u64) cold(source, i)
        sum = (sum << 3) ^ (sum >> 61) ^ v0 ^ v3 ^ v6 ^ v9
    }
    return sum + v1 + v4 + v7 + v10
}

#[Swag.Optimize(true), Swag.NoInline]
func scanMutable(source: [*] u64, rounds, mask, stop: u64)->u64
{
    var v0  = source[0]
    var v1  = source[1]
    var v2  = source[2]
    var v3  = source[3]
    var v4  = source[4]
    var v5  = source[5]
    var v6  = source[6]
    var v7  = source[7]
    var v8  = source[8]
    var v9  = source[9]
    var v10 = source[10]
    var v11 = source[11]
    var sum = 0'u64
    for i in rounds
    {
        if i == stop do
            break
        v0  += (v1 ^ i) + 1
        v1  += (v2 ^ i) + 2
        v2  += (v3 ^ i) + 3
        v3  += (v4 ^ i) + 4
        v4  += (v5 ^ i) + 5
        v5  += (v6 ^ i) + 6
        v6  += (v7 ^ i) + 7
        v7  += (v8 ^ i) + 8
        v8  += (v9 ^ i) + 9
        v9  += (v10 ^ i) + 10
        v10 += (v11 ^ i) + 11
        v11 += (v0 ^ i) + 12
        sum += ((v0 ^ v1) + (v2 ^ v3) + (v4 ^ v5) + (v6 ^ v7) + (v8 ^ v9) + (v10 ^ v11)) * (i + 1)
        if i & mask == 0 do
            sum ^= cast(u64) cold(source, i)
        sum = (sum << 3) ^ (sum >> 61) ^ v0 ^ v3 ^ v6 ^ v9
    }
    return sum + v1 + v4 + v7 + v10
}

#[Swag.Optimize(false), Swag.NoInline]
func mutableReference(source: [*] u64, rounds, mask, stop: u64)->u64
{
    var v0  = source[0]
    var v1  = source[1]
    var v2  = source[2]
    var v3  = source[3]
    var v4  = source[4]
    var v5  = source[5]
    var v6  = source[6]
    var v7  = source[7]
    var v8  = source[8]
    var v9  = source[9]
    var v10 = source[10]
    var v11 = source[11]
    var sum = 0'u64
    for i in rounds
    {
        if i == stop do
            break
        v0  += (v1 ^ i) + 1
        v1  += (v2 ^ i) + 2
        v2  += (v3 ^ i) + 3
        v3  += (v4 ^ i) + 4
        v4  += (v5 ^ i) + 5
        v5  += (v6 ^ i) + 6
        v6  += (v7 ^ i) + 7
        v7  += (v8 ^ i) + 8
        v8  += (v9 ^ i) + 9
        v9  += (v10 ^ i) + 10
        v10 += (v11 ^ i) + 11
        v11 += (v0 ^ i) + 12
        sum += ((v0 ^ v1) + (v2 ^ v3) + (v4 ^ v5) + (v6 ^ v7) + (v8 ^ v9) + (v10 ^ v11)) * (i + 1)
        if i & mask == 0 do
            sum ^= cast(u64) cold(source, i)
        sum = (sum << 3) ^ (sum >> 61) ^ v0 ^ v3 ^ v6 ^ v9
    }
    return sum + v1 + v4 + v7 + v10
}

#test
{
    for seed in [0'u64, 1, 0x123456789ABCDEF0, 0xFFFFFFFFFFFFFFFF]
    {
        for rounds in [0'u64, 1, 2, 17, 65]
        {
            for mask in [0'u64, 3, 31]
            {
                var actual: [12] u64
                for i in 12 do
                    actual[i] = seed + i * 0x17ABCDEF
                var expected = actual
                Swag.assert(scan(&actual[0], rounds, mask) == reference(&expected[0], rounds, mask))
                Swag.assert(scanMutable(&actual[0], rounds, mask, rounds / 2) == mutableReference(&expected[0], rounds, mask, rounds / 2))
                for i in 12 do
                    Swag.assert(actual[i] == expected[i])
            }
        }
    }
}
