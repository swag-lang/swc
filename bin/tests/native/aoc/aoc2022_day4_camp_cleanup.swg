#global fileprivate

const Input = """2-4,6-8
                 2-3,4-5
                 5-7,7-9
                 2-8,3-7
                 6-6,4-6
                 2-6,4-8"""

func num(b: const [..] u8, p: *u64)->u32
{
    var n: u32
    while dref p < @countof(b) and b[dref p] >= '0''u8 and b[dref p] <= '9''u8
    {
        n = n * 10 + (b[dref p] - '0''u8)
        dref p += 1
    }
    if dref p < @countof(b) do dref p += 1
    return n
}

func solve(b: const [..] u8)->[2] u32
{
    var r: [2] u32
    var i: u64
    while i < @countof(b)
    {
        if b[i] < '0''u8 or b[i] > '9''u8 { i += 1; continue }
        let a = num(b, &i), b2 = num(b, &i), c = num(b, &i), d = num(b, &i)
        if (a <= c and b2 >= d) or (c <= a and d >= b2) do r[0] += 1
        if a <= d and c <= b2 do r[1] += 1
    }
    return r
}

const CT = #run solve(Input)
#assert(CT[0] == 2 and CT[1] == 4)

#test
{
    let r = solve(Input)
    @assert(r[0] == 2 and r[1] == 4)
}
