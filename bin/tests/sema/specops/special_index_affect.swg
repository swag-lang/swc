#global fileprivate

struct WriteOnlyIndexBox
{
    first:  s32
    second: s32
}

impl WriteOnlyIndexBox
{
    #[Swag.Overload]
    mtd opIndexAffect(index: s32, value: s32)
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
