#global fileprivate

struct CannotCastConstBox
{
    value: s32
}

#test
{
    var x: *s32 = null
    var y: const *s32 = null

    var y0 = cast(const *s32) x
    var x0 = cast(*s32) y0 // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var x: const *s32 = null
    var y = cast(*u8) x // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var text: cstring = cast(cstring) @dataof("abc")
    var bytes = cast([..] u8) text // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var bytes = cast([..] u8) (cast(cstring) @dataof("abc")) // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var value = 1's32
    let ptr: const *s32 = &value
    let boxed = @mkany(ptr, s32)
    let data = cast(*s32) @dataof(boxed) // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var value = 1's32
    let ptr: const *s32 = &value
    let boxed = @mkany(ptr, s32)
    let data = cast(*s32) boxed // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var data: [2] u8 = [1, 2]
    let bytes: const [..] u8 = cast(const [..] u8) data
    let boxed = @mkany(&bytes, const [..] u8)
    let mutable = cast([..] u8) boxed // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var value = 1's32
    let ptr: const *s32 = &value
    var boxed: any = @mkany(ptr, s32) // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var value = 1's32
    let ptr: const *s32 = &value
    let raw = cast(*void) ptr // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    const data: [2] u8 = [1, 2]
    let ptr = cast([*] u8) data // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    const value: CannotCastConstBox = {value: 1}
    let ptr = cast(*CannotCastConstBox) value // swc-expected-error {{sema_err_cannot_cast_const}}
}
