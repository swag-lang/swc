#global internal

#test
{
    for to 4 {}
    for until 4 {}
    for 4 to 4 {}
    for 4 until 4 {} // swc-expected-error {{sema_err_range_invalid_bounds}}
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

#test
{
    for 5 until 4 {} // swc-expected-error {{sema_err_range_invalid_bounds}}
}

#test
{
    for "a" to 4 {} // swc-expected-error {{sema_err_invalid_range_type}}
}

#test
{
    for to "a" {} // swc-expected-error {{sema_err_invalid_range_type}}
}
