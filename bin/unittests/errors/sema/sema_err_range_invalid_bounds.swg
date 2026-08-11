#global private

#test
{
    for 4 to 4 {}

    // An exclusive range with equal bounds is empty, not invalid.
    for 4 until 4 {}
}

#test
{
    var a: f32
    switch (a)
    {
    case 1 to 2.0: break
    case 1.0 to 2: break
    }
}

#test
{
    for 5 until 4 {}     // swc-expected-error {{sema_err_range_invalid_bounds}}
}

#test
{
    for 5 to 4 {}     // swc-expected-error {{sema_err_range_invalid_bounds}}
}

#test
{
    let values = [10, 20, 30]
    discard values[2 until 1]     // swc-expected-error {{sema_err_range_invalid_bounds}}
}

#test
{
    let values = [10, 20, 30]
    discard values[2 to 1]     // swc-expected-error {{sema_err_range_invalid_bounds}}
}

// Slicing with equal bounds is empty, not invalid.
#test
{
    let values = [10, 20, 30]
    discard values[2 until 2]
    discard values[0 until 0]
}
