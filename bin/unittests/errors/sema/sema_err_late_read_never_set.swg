#global private

struct LateItem
{
    value: s32
}

struct LateOwner
{
    late item: *LateItem
}

func readBeforeSet()->s32
{
    var owner: LateOwner
    return owner.item.value     // swc-expected-error {{sema_err_late_read_never_set}}
}
