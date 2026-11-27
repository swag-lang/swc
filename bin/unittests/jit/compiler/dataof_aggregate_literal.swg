#global private

#test
{
    let p = ([1, 2.5]).buffer

    #assert(#typeof(p) == const [*] f32)
    Swag.require(p[] == 1.0_f32)
    Swag.require(p[1] == 2.5_f32)
}
