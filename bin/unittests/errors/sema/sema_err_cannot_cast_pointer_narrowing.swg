#global private

// An address goes into an integer at least as wide as a pointer. A narrower destination
// would silently drop its high half, so the widening has to be written down.

enum NarrowPointerKind: u32 { First }

#test
{
    var storage: [4] u8
    let p   = @dataof(storage)
    let bad = cast(u32) p     // swc-expected-error {{sema_err_cannot_cast_pointer_narrowing}}
}

#test
{
    var storage: [4] u8
    let p   = @dataof(storage)
    let bad = cast(s32) p     // swc-expected-error {{sema_err_cannot_cast_pointer_narrowing}}
}

#test
{
    // An enum destination is judged on its underlying type.
    var storage: [4] u8
    let p   = @dataof(storage)
    let bad = cast(NarrowPointerKind) p     // swc-expected-error {{sema_err_cannot_cast_pointer_narrowing}}
}
