#global fileprivate // swc-option suite-test

#test
{
    var a: s32
    var b: s32
    a, b = 1
    a, b += 1
}


#test
{
    var a: s32
    var b: s32
    a, ?, b = 1
}




#test
{
    var a: f32
    var b: s32
    a, b = 1
}


#test
{
    var a: [*] u8
    a += 1
    a -= 1
}
