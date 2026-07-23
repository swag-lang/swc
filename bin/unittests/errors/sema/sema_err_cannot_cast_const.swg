#global private

struct CannotCastConstBox
{
    value: s32
}

interface ICannotCastConst {}

impl ICannotCastConst for CannotCastConstBox {}

#test
{
    var xv: s32
    var x:  *s32 = &xv
    var y:  const *s32 = &xv

    var y0 = cast(const *s32) x
    var x0 = cast(*s32) y0     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var xv: s32
    var x:  const *s32 = &xv
    var y = cast(*u8) x     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var text: const cstring = cast(const cstring) @dataof("abc")
    var bytes = cast([..] u8) text     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var bytes = cast([..] u8) (cast(const cstring) @dataof("abc"))     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var value = 1's32
    let ptr: const *s32 = &value
    let boxed = @mkany(ptr, s32)
    let data = cast(*s32) @dataof(boxed)     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var value = 1's32
    let ptr: const *s32 = &value
    let boxed = @mkany(ptr, s32)
    let data = cast(*s32) boxed     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var data:  [2] u8 = [1, 2]
    let bytes: const [..] u8 = cast(const [..] u8) data
    let boxed = @mkany(&bytes, const [..] u8)
    let mutable = cast([..] u8) boxed     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var value = 1's32
    let ptr:   const *s32 = &value
    var boxed: any = @mkany(ptr, s32)     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var value = 1's32
    let ptr: const *s32 = &value
    let raw = cast(*void) ptr     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    const data: [2] u8 = [1, 2]
    let ptr = cast([*] u8) data     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    const data: [2] u8 = [1, 2]
    let bytes = cast([..] u8) data     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    const value: CannotCastConstBox = {value: 1}
    let ptr = cast(*CannotCastConstBox) value     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    const data: [3] u8 = ['a''u8, 'b''u8, 0]
    let text = cast(cstring) data     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var data: [3] u8 = ['a''u8, 'b''u8, 0]
    let ptr:  const [*] u8 = cast(const [*] u8) &data[0]
    let text = cast(cstring) ptr     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var value: CannotCastConstBox = {value: 1}
    let ptr:   const *CannotCastConstBox = &value
    let itf = @mkinterface(ptr, CannotCastConstBox, ICannotCastConst)
    let raw = cast(*CannotCastConstBox) @dataof(itf)     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var data: [3] u8 = ['a''u8, 'b''u8, 0]
    let text: const cstring = cast(const cstring) &data[0]
    let boxed = @mkany(&text, const cstring)
    let mutable = cast(cstring) boxed     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var value: CannotCastConstBox = {value: 1}
    let ptr:   const *CannotCastConstBox = &value
    let itf = @mkinterface(ptr, CannotCastConstBox, ICannotCastConst)
    let boxed = @mkany(&itf, const ICannotCastConst)
    let mutable = cast(ICannotCastConst) boxed     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var data:  [3] u8 = ['a''u8, 'b''u8, 0]
    let text:  const cstring = cast(const cstring) &data[0]
    var boxed: any = text     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    const value: CannotCastConstBox = {value: 1}
    var itf: ICannotCastConst = value     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var value: CannotCastConstBox = {value: 1}
    let ptr:   const *CannotCastConstBox = &value
    var itf:   ICannotCastConst = dref ptr     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var value: CannotCastConstBox = {value: 1}
    let ref:   const &CannotCastConstBox = &value
    let itf = @mkinterface(ref, CannotCastConstBox, ICannotCastConst)
    let raw = cast(*CannotCastConstBox) @dataof(itf)     // swc-expected-error {{sema_err_cannot_cast_const}}
}
