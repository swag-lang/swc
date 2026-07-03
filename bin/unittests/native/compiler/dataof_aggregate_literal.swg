#global private

#test
{
    let p = @dataof([1, 5_000_000_000])

    #assert(#typeof(p) == const [*] s64)
    @assert(dref p == 1's64)
    @assert(p[1] == 5_000_000_000's64)
}
