#global private

// A zero-initialized local array whose elements are read before they are all
// written. The backend splits that fill so the elements can live in registers,
// so every element must still start at zero - including the ones the code never
// assigns. Each case is checked against the same computation written with
// plain scalars, which takes a different path through the backend.

#[Swag.NoInline]
func mixArray(seed: u32)->u32
{
    var acc: [4] u32
    acc[0] = seed

    for 8
    {
        acc[0] += acc[1]
        acc[1] ^= acc[2]
        acc[2] += acc[3]
        acc[3] ^= acc[0]
    }

    return acc[0] ^ acc[1] ^ acc[2] ^ acc[3]
}

#[Swag.NoInline]
func mixScalars(seed: u32)->u32
{
    var a0 = seed
    var a1 = 0'u32
    var a2 = 0'u32
    var a3 = 0'u32

    for 8
    {
        a0 += a1
        a1 ^= a2
        a2 += a3
        a3 ^= a0
    }

    return a0 ^ a1 ^ a2 ^ a3
}

#[Swag.NoInline]
func untouchedTail(seed: u64)->u64
{
    var acc: [4] u64
    acc[1] = seed
    return acc[0] + acc[1] + acc[2] + acc[3]
}

#[Swag.NoInline]
func oneWriteThenSum(index: u64, value: u32)->u32
{
    var acc: [8] u32
    acc[index] = value
    var total = 0'u32
    for i in 8 do
        total += acc[i]
    return total
}

#test
{
    for i in 16'u32 do
        Swag.assert(mixArray(i) == mixScalars(i))

    Swag.assert(untouchedTail(0) == 0)
    Swag.assert(untouchedTail(12_345) == 12_345)

    Swag.assert(oneWriteThenSum(0, 5) == 5)
    Swag.assert(oneWriteThenSum(7, 5) == 5)
    Swag.assert(oneWriteThenSum(3, 0) == 0)
}
