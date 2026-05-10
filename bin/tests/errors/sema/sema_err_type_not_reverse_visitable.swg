#global fileprivate

struct MissingReverseVisitBox
{
    value: s32
}

#test
{
    let values = MissingReverseVisitBox{}
    foreach #reverse value in values {} // swc-expected-error {{sema_err_type_not_reverse_visitable}}
}
