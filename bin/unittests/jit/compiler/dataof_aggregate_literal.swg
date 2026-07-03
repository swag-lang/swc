#global private

#test
{
    let p = @dataof([1, 2.5])

    #assert(#typeof(p) == const [*] f32)
    @assert(dref p == 1.0'f32)
    @assert(p[1] == 2.5'f32)
}
