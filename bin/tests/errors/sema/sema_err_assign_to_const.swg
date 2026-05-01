#global fileprivate

struct WriteOnlyIndexBox
{
    first:  s32
    second: s32
}

impl WriteOnlyIndexBox
{
    mtd opIndexSet(index: s32, value: s32)
    {
        if index == 0 do
            .first = value
        else do
            .second = value
    }
}

struct WriteOnlyIndexHolder
{
    value: WriteOnlyIndexBox
}

#test
{
    var box = WriteOnlyIndexBox{}
    box[0] = 7

    var holder = WriteOnlyIndexHolder{}
    holder.value[0] = 3

    #assert(#typeof(box) == WriteOnlyIndexBox)
}

#test
{
    const box = WriteOnlyIndexBox{}
    box[0] = 1 // swc-expected-error {{sema_err_assign_to_const}}
}

#test
{
    var text: const cstring = cast(const cstring) @dataof("abc")
    text[0] = 'A''u8 // swc-expected-error {{sema_err_assign_to_const}}
}

#test
{
    var text: cstring = cast(cstring) @dataof("abc")
    text[0] = 'A''u8 // swc-expected-error {{sema_err_assign_to_const}}
}

#test
{
    var text: string = "abc"
    text[0] = 'A''u8 // swc-expected-error {{sema_err_assign_to_const}}
}

#test
{
    var text: string = "abc"
    foreach &value in text
    {
        dref value = 'A''u8 // swc-expected-error {{sema_err_assign_to_const}}
    }
}

#test
{
    var text: cstring = cast(cstring) @dataof("abc")
    foreach &value in text
    {
        dref value = 'A''u8 // swc-expected-error {{sema_err_assign_to_const}}
    }
}

#test
{
    var data: [3] u8 = [1, 2, 3]
    let values: const [..] u8 = cast(const [..] u8) data
    values[0] = 9'u8 // swc-expected-error {{sema_err_assign_to_const}}
}

#test
{
    let bytes = cast(const [..] u8) (cast(const cstring) @dataof("abc"))
    bytes[0] = 'A''u8 // swc-expected-error {{sema_err_assign_to_const}}
}

#test
{
    var data: [3] u8 = [1, 2, 3]
    let ptr: const [*] u8 = cast(const [*] u8) &data[0]
    ptr[0] = 9'u8 // swc-expected-error {{sema_err_assign_to_const}}
}

#test
{
    var value = 1's32
    let ptr: const *s32 = &value
    dref ptr = 2's32 // swc-expected-error {{sema_err_assign_to_const}}
}
