#global private

#[Swag.NoInline]
func results32(value: u32, output: [*] u32)
{
    output[0]  = value / 14
    output[1]  = value % 14
    output[2]  = value / 28
    output[3]  = value % 28
    output[4]  = value / 56
    output[5]  = value % 56
    output[6]  = value / 70
    output[7]  = value % 70
    output[8]  = value / 1000
    output[9]  = value % 1000
    output[10] = value / 1000000
    output[11] = value % 1000000
    output[12] = value / 4294967294
    output[13] = value % 4294967294
    output[14] = value
}

#[Swag.NoInline, Swag.Optimize(false)]
func reference32(value, divisor: u32, output: [*] u32)
{
    output[0] = value / divisor
    output[1] = value % divisor
}

#[Swag.NoInline]
func results64(value: u64, output: [*] u64)
{
    output[0]  = value / 14
    output[1]  = value % 14
    output[2]  = value / 28
    output[3]  = value % 28
    output[4]  = value / 56
    output[5]  = value % 56
    output[6]  = value / 70
    output[7]  = value % 70
    output[8]  = value / 1000
    output[9]  = value % 1000
    output[10] = value / 1000000
    output[11] = value % 1000000
    output[12] = value / 18446744073709551614
    output[13] = value % 18446744073709551614
    output[14] = value / 13835058055282163712
    output[15] = value % 13835058055282163712
    output[16] = value / 3458764513820540928
    output[17] = value % 3458764513820540928
    output[18] = value
}

#[Swag.NoInline, Swag.Optimize(false)]
func reference64(value, divisor: u64, output: [*] u64)
{
    output[0] = value / divisor
    output[1] = value % divisor
}

#test
{
    let divisors   = [14'u32, 28, 56, 70, 1000, 1000000, 4294967294]
    let boundaries = [0'u32, 1, 0xFFFFFFFF, 0x80000000]
    var actual:   [15] u32
    var expected: [2] u32
    var state      = 0x9E3779B9'u32
    for sample in 512
    {
        var value = state
        if sample < boundaries.count do
            value = boundaries[sample]
        results32(value, &actual[0])
        for divisor, i in divisors
        {
            reference32(value, divisor, &expected[0])
            Swag.assert(actual[i * 2] == expected[0])
            Swag.assert(actual[i * 2 + 1] == expected[1])
        }
        Swag.assert(actual[14] == value)
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
    }

    for divisor in divisors
    {
        let lastMultiple = 0xFFFFFFFF'u32 - 0xFFFFFFFF'u32 % divisor
        for value in [divisor - 1, divisor, divisor + 1, lastMultiple - 1, lastMultiple, lastMultiple + 1]
        {
            results32(value, &actual[0])
            for tested, i in divisors
            {
                reference32(value, tested, &expected[0])
                Swag.assert(actual[i * 2] == expected[0])
                Swag.assert(actual[i * 2 + 1] == expected[1])
            }
        }
    }
}

#test
{
    let divisors   = [14'u64, 28, 56, 70, 1000, 1000000, 18446744073709551614, 13835058055282163712, 3458764513820540928]
    let boundaries = [0'u64, 1, 0xFFFFFFFFFFFFFFFF, 0x8000000000000000]
    var actual:   [19] u64
    var expected: [2] u64
    var state      = 0x9E3779B9'u64
    for sample in 512
    {
        var value = state
        if sample < boundaries.count do
            value = boundaries[sample]
        results64(value, &actual[0])
        for divisor, i in divisors
        {
            reference64(value, divisor, &expected[0])
            Swag.assert(actual[i * 2] == expected[0])
            Swag.assert(actual[i * 2 + 1] == expected[1])
        }
        Swag.assert(actual[18] == value)
        state ^= state << 13
        state ^= state >> 17
        state ^= state << 5
    }

    for divisor in divisors
    {
        let lastMultiple = 0xFFFFFFFFFFFFFFFF'u64 - 0xFFFFFFFFFFFFFFFF'u64 % divisor
        for value in [divisor - 1, divisor, divisor + 1, lastMultiple - 1, lastMultiple, lastMultiple + 1]
        {
            results64(value, &actual[0])
            for tested, i in divisors
            {
                reference64(value, tested, &expected[0])
                Swag.assert(actual[i * 2] == expected[0])
                Swag.assert(actual[i * 2 + 1] == expected[1])
            }
        }
    }
}
