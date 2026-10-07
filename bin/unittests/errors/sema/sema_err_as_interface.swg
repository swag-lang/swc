#global private

interface IFoo
{
    mtd value()->s32
}

struct Missing {}

#test
{
    var value: Missing
    discard cast(IFoo, &value)     // swc-expected-error {{sema_err_fallible_cast_requires_handler}}
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
    discard catch cast(IFoo?, pointer)     // swc-expected-error {{sema_err_cannot_cast_const}}
}

#test
{
    var value = Present{}
    let pointer: const *Present = &value
    discard cast(IFoo, pointer)     // swc-expected-error {{sema_err_cannot_cast_const}}
}
