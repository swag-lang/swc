#global private

struct LateItem
{
    value: s32
}

struct LateOwner
{
    item: #late *LateItem
}

func readBeforeSet()->s32
{
    var owner: LateOwner
    return owner.item.value     // swc-expected-error {{sema_err_late_read_never_set}}
}
