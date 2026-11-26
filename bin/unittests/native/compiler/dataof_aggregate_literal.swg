#global private

#test
{
    let p = ([1, 5_000_000_000]).buffer

    #assert(#typeof(p) == const [*] s64)
    Swag.require(p[] == 1_s64)
    Swag.require(p[1] == 5_000_000_000_s64)
}
