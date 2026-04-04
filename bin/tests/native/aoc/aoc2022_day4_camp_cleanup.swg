#global fileprivate

const Input =
"""2-4,6-8
   2-3,4-5
   5-7,7-9
   2-8,3-7
   6-6,4-6
   2-6,4-8"""

func num(bytes: const [..] u8, p: *u64)->u32
{
    var n: u32
    while dref p < @countof(bytes) and bytes[dref p] >= '0''u8 and bytes[dref p] <= '9''u8
    {
        n = n * 10 + (bytes[dref p] - '0''u8)
        dref p += 1
    }
    if dref p < @countof(bytes) do dref p += 1
    return n
}

func solve(bytes: const [..] u8)->[2] u32
{
    var r: [2] u32
    var i: u64
    while i < @countof(bytes)
    {
        if bytes[i] < '0''u8 or bytes[i] > '9''u8 { i += 1; continue }
        let a = num(bytes, &i), b = num(bytes, &i), c = num(bytes, &i), d = num(bytes, &i)
        if (a <= c and b >= d) or (c <= a and d >= b) do r[0] += 1
        if a <= d and c <= b do r[1] += 1
    }
    return r
}

const CT = #run solve(cast(const [..] u8) Input)
#assert(CT[0] == 2)
#assert(CT[1] == 4)

#test
{
    let r = solve(cast(const [..] u8) Input)
    @assert(r[0] == 2)
    @assert(r[1] == 4)
}
