#global private

interface IFoo
{
    mtd value()->s32
}

struct Missing {}

#test
{
    var value: Missing
    discard (&value) as IFoo     // swc-expected-error {{sema_err_cannot_cast_to_interface}}
}

struct Present {}

impl IFoo for Present
{
    mtd value()->s32 => 1
}

#test
{
    var value = Present{}
    let pointer: const *Present = &value
    discard pointer as IFoo     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var value = Present{}
    let pointer: const *Present = &value
    discard cast(IFoo) pointer     // swc-expected-error {{sema_err_cannot_cast_const}}
}
