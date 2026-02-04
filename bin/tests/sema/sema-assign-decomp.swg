#global internal

struct Pair { a: s32; b: bool }

#test
{
    var s: Pair
    var a: s32
    var b: bool
    (a, b) = s
}

#test
{
    var s: Pair
    var a: s32
    (a, ?) = s
}

#test
{
    var a: s32
    var b: s32
    (a, b) = 1 // swc-expected-error {{sema_err_decomposition_not_struct}}
}

#test
{
    var s: Pair
    var a: s32
    var b: bool
    var c: s32
    (a, b, c) = s // swc-expected-error {{sema_err_decomposition_too_many_names}}
}

#test
{
    var s: Pair
    var a: s32
    (a) = s // swc-expected-error {{sema_err_decomposition_not_enough_names}}
}

#test
{
    var s: Pair
    var a: s32
    var b: s32
    (a, b) = s // swc-expected-error {{sema_err_cannot_cast}}
}
