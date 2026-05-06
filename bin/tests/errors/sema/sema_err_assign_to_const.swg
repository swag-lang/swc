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

struct ConstAssignPair
{
    value: s32
}

struct ConstAssignArrayBox
{
    bytes: [2] u8
}

struct InlineConstAssignPayload
{
    total: s32
}

impl InlineConstAssignPayload
{
    mtd bump()
    {
        .total += 1
    }
}

#[Swag.Macro]
func macroAssignConstParam(payload: InlineConstAssignPayload)
{
    payload.total += 1 // swc-expected-error {{sema_err_assign_to_const}}
}

#[Swag.Mixin]
func mixinAssignConstParam(values: [2] s32)
{
    values[1] += 1 // swc-expected-error {{sema_err_assign_to_const}}
}

#[Swag.Macro]
func macroForeachWriteConstParam(values: [2] s32)
{
    foreach &value in values
    {
        dref value += 1 // swc-expected-error {{sema_err_assign_to_const}}
    }
}

#[Swag.Mixin]
func mixinForeachWriteConstParam(values: [2] s32)
{
    foreach &value in values
    {
        dref value += 1 // swc-expected-error {{sema_err_assign_to_const}}
    }
}

func plainCallMutableMethod(payload: InlineConstAssignPayload)
{
    payload.bump() // swc-expected-error {{sema_err_cannot_cast_const}}
}

func plainAssignConstParam(payload: InlineConstAssignPayload)
{
    payload.total += 1 // swc-expected-error {{sema_err_assign_to_const}}
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
    var text: const cstring = cast(const cstring) @dataof("abc")
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
    var text: const cstring = cast(const cstring) @dataof("abc")
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

#test
{
    var data: [2] ConstAssignPair = [{value: 1}, {value: 2}]
    let values: const [..] ConstAssignPair = cast(const [..] ConstAssignPair) data
    values[0].value = 9 // swc-expected-error {{sema_err_assign_to_const}}
}

#test
{
    var data: [2] ConstAssignPair = [{value: 1}, {value: 2}]
    let ptr: const [*] ConstAssignPair = cast(const [*] ConstAssignPair) &data[0]
    ptr[0].value = 9 // swc-expected-error {{sema_err_assign_to_const}}
}

#test
{
    var value: ConstAssignPair = {value: 1}
    let ptr: const *ConstAssignPair = &value
    ptr.value = 9 // swc-expected-error {{sema_err_assign_to_const}}
}

#test
{
    var data: [2] ConstAssignPair = [{value: 1}, {value: 2}]
    let values: const [..] ConstAssignPair = cast(const [..] ConstAssignPair) data
    let ptr = &values[0].value
    dref ptr = 9 // swc-expected-error {{sema_err_assign_to_const}}
}

#test
{
    var data: [2] ConstAssignPair = [{value: 1}, {value: 2}]
    let values: const [*] ConstAssignPair = cast(const [*] ConstAssignPair) &data[0]
    let ptr = &values[0].value
    dref ptr = 9 // swc-expected-error {{sema_err_assign_to_const}}
}

#test
{
    var data: [1] ConstAssignArrayBox = [{bytes: [1'u8, 2'u8]}]
    let values: const [..] ConstAssignArrayBox = cast(const [..] ConstAssignArrayBox) data
    let ptr = @dataof(values[0].bytes)
    ptr[0] = 9'u8 // swc-expected-error {{sema_err_assign_to_const}}
}

#test
{
    var data: [1] ConstAssignArrayBox = [{bytes: [1'u8, 2'u8]}]
    let values: const [*] ConstAssignArrayBox = cast(const [*] ConstAssignArrayBox) &data[0]
    let ptr = @dataof(values[0].bytes)
    ptr[0] = 9'u8 // swc-expected-error {{sema_err_assign_to_const}}
}

#test
{
    var payload = InlineConstAssignPayload{total: 41}
    macroAssignConstParam(payload)
}

#test
{
    var values: [2] s32 = [1, 2]
    mixinAssignConstParam(values)
}

#test
{
    var values: [2] s32 = [1, 2]
    macroForeachWriteConstParam(values)
}

#test
{
    var values: [2] s32 = [1, 2]
    mixinForeachWriteConstParam(values)
}

#test
{
    var payload = InlineConstAssignPayload{total: 41}
    plainCallMutableMethod(payload)
}

#test
{
    var payload = InlineConstAssignPayload{total: 41}
    plainAssignConstParam(payload)
}
