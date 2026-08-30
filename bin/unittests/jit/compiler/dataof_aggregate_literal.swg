#global private

#test
{
    let p = ([1, 2.5]).buffer

    #assert(#typeof(p) == const [*] f32)
    Swag.assert(p[] == 1.0'f32)
    Swag.assert(p[1] == 2.5'f32)
}
