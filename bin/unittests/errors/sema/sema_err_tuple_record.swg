#global private

#test
{
    let point = {x: 10, y: 20}
    let (first, second) = point // swc-expected-error {{sema_err_decomposition_kind}}
}

#test
{
    let pair = (10, 20)
    let {item0: first, item1: second} = pair // swc-expected-error {{sema_err_decomposition_kind}}
}

#test
{
    var point = {x: 10, y: 20}
    point = (30, 40) // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var pair = (10, 20)
    pair = {x: 30, y: 40} // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    var point = {x: 10, y: 20}
    point = {width: 30, height: 40} // swc-expected-error {{sema_err_cannot_cast}}
}

#test
{
    let point = {x: 10, x: 20} // swc-expected-error {{sema_err_record_duplicate_field}}
}

#test
{
    let point = {10, 20} // swc-expected-error {{sema_err_record_needs_field_name}}
}

#[Swag.NoCopy]
struct RecordHandle { value: s32 }
impl RecordHandle { mtd opDrop() {} }

#test
{
    let source = {handle: RecordHandle{7}, count: 2}
    let {handle} = source // swc-expected-error {{sema_err_cannot_copy_nocopy}}
}

#test
{
    let source = {handle: RecordHandle{7}, count: 2}
    var target: RecordHandle
    {handle: target} = source // swc-expected-error {{sema_err_cannot_copy_nocopy}}
}

#test
{
    let source = {handle: RecordHandle{7}, count: 2}
    var target: {count: s32, handle: RecordHandle} = source // swc-expected-error {{sema_err_cannot_copy_nocopy}}
}

#test
{
    let source = {handle: RecordHandle{7}, count: 2}
    let copied = source // swc-expected-error {{sema_err_cannot_copy_nocopy}}
}

#test
{
    let source = (RecordHandle{7}, 2)
    let copied = source // swc-expected-error {{sema_err_cannot_copy_nocopy}}
}

struct ReturnElement { x, y: s32 }

func returnTupleInStructArray()->[1] ReturnElement
{
    return [(1, 2)]     // swc-expected-error {{cannot cast from '(integer, integer)' to 'ReturnElement'}}
}
