#global fileprivate // swc-option suite-test

#test
{
    for to 4 {}
    for until 4 {}
    for 4 to 4 {}
}

#test
{
    var a: f32
    switch(a)
    {
    case 1 to 2.0: break
    case 1.0 to 2: break
    }
}



