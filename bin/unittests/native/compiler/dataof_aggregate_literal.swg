#global private

#test
{
    let p = ([1, 5_000_000_000]).buffer

    #assert(#typeof(p) == const [*] s64)
    Swag.assert(p[] == 1's64)
    Swag.assert(p[1] == 5_000_000_000's64)
}
